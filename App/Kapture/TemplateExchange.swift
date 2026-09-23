import AppKit
import KaptureKit
import UniformTypeIdentifiers

extension UTType {
    /// Its own extension rather than a claim on `public.json`, or Kapture would
    /// become the system's handler for every JSON file on the machine (ADR-017).
    static let kaptureTemplate = UTType(
        exportedAs: "com.eriklarson.kapture.template", conformingTo: .json
    )
}

/// The count of strips already using the template is taken once, when the
/// sheet opens, rather than read off disk on every redraw of a slider.
struct TemplateEdit: Identifiable {
    var template: StripTemplate
    var stripsInUse: Int
    /// True when a built-in was duplicated to get here, so the edit is a new
    /// template rather than a change to one that exists.
    var isCopy: Bool

    var id: String { template.id }

    func replacing(_ edited: StripTemplate) -> TemplateEdit {
        var copy = self
        copy.template = edited
        return copy
    }
}

extension BoothModel {
    /// Whether the selected template is one of the user's, and so removable.
    /// A built-in is not: it is a constant in the binary.
    var canRemoveTemplate: Bool {
        userTemplates.contains { $0.id == templateID }
    }

    /// The strip's own overrides are baked in on purpose: the file is what the
    /// paper currently looks like, not what its template started as.
    func saveTemplate() async {
        guard strip != nil else { return }
        let source = shownTemplate

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.kaptureTemplate]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(source.name) Copy.kapturetemplate"
        panel.message = "Save this strip's layout as a template you can use again."
        guard await panel.begin() == .OK, let url = panel.url else { return }

        do {
            let template = source.derived(
                name: url.deletingPathExtension().lastPathComponent
            )
            // Encoding validates, so a layout that could never be imported is
            // refused before anything reaches disk.
            let data = try TemplateImport.encode(template)
            try data.write(to: url)
            try templateStore.install(template)
            reloadTemplates()
            report("Saved \u{201C}\(template.name)\u{201D}. It is in the template list.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Files written before the format had an extension of its own are still
    /// plain `.json`, so both are offered.
    func importTemplate() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.kaptureTemplate, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Kapture template file."
        guard await panel.begin() == .OK, let url = panel.url else { return }
        await importTemplate(at: url)
    }

    /// Replaces a template already in the list and re-renders every strip naming
    /// it. Split from the panel so a Finder double-click arrives the same way.
    func importTemplate(at url: URL) async {
        do {
            let template = try TemplateImport.decode(try Data(contentsOf: url))
            let outcome = try templateStore.install(template)
            reloadTemplates()
            let affected = stripsUsing(template.id)
            switch outcome {
            case .added:
                report("Added \u{201C}\(template.name)\u{201D}.")
            case .replaced where affected == 0:
                report("Replaced \u{201C}\(template.name)\u{201D}.")
            case .replaced:
                report(
                    "Replaced \u{201C}\(template.name)\u{201D}. "
                        + (affected == 1
                            ? "1 past strip will re-render."
                            : "\(affected) past strips will re-render.")
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Nothing reference-counts a template, so this is the check that stands
    /// between a tidy-up and a strip that cannot render (ADR-011).
    func removeTemplate() async {
        guard let template = userTemplates.first(where: { $0.id == templateID }) else { return }
        do {
            let inUse = stripsUsing(template.id)
            guard inUse == 0 else {
                errorMessage = "\u{201C}\(template.name)\u{201D} cannot be removed. "
                    + (inUse == 1
                        ? "1 strip still needs it to render."
                        : "\(inUse) strips still need it to render.")
                return
            }
            try templateStore.remove(id: template.id)
            reloadTemplates()
            // The picker's selection has just stopped existing.
            templateID = BuiltInTemplates.classicStrip.id
            report("Removed \u{201C}\(template.name)\u{201D}.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A built-in is duplicated first: redefining `classic-strip` would move
    /// every strip ever shot with it (same reason `TemplateImport` refuses its id).
    func editTemplate() {
        let selected = templates[templateID] ?? BuiltInTemplates.classicStrip
        let isBuiltIn = BuiltInTemplates.byID[selected.id] != nil
        editingTemplate = TemplateEdit(
            template: isBuiltIn
                ? selected.derived(name: "\(selected.name) Copy")
                : selected,
            // A copy has no id on disk yet, so nothing can be naming it.
            stripsInUse: isBuiltIn ? 0 : stripsUsing(selected.id),
            isCopy: isBuiltIn
        )
    }

    /// A shown strip naming it is re-rendered here: a template edit changes
    /// what a recipe *means*, not what it says, so `restyle` wouldn't notice.
    func applyEdit(_ edit: TemplateEdit) async {
        do {
            try templateStore.install(edit.template)
            reloadTemplates()
            let name = "\u{201C}\(edit.template.name)\u{201D}"

            if edit.isCopy {
                // Leaving them on the built-in would make the sheet a silent
                // no-op, so this moves the selection when the strip fits.
                let fits = strip == nil
                    || edit.template.frameCount == strip?.recipe.frameIDs.count
                if fits { await selectTemplate(edit.template.id) }
                report(
                    fits
                        ? "Saved \(name) and selected it. The built-in is unchanged."
                        : "Saved \(name). It holds \(edit.template.frameCount) photos, "
                            + "so this strip stays where it is."
                )
            } else {
                if strip?.recipe.templateID == edit.template.id { await refreshStrip() }
                report(
                    edit.stripsInUse > 1
                        ? "Updated \(name). \(edit.stripsInUse) past strips will re-render."
                        : "Updated \(name)."
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A listing that can't be read counts as none: refusing to tidy up because
    /// the directory is unreadable would be the wrong failure.
    func stripsUsing(_ id: String) -> Int {
        ((try? store.listRecipes()) ?? []).filter { $0.templateID == id }.count
    }
}
