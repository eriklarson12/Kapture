import AppKit
import KaptureKit
import UniformTypeIdentifiers

extension UTType {
    /// The template format, declared in the app's Info.plist.
    ///
    /// Its own extension rather than a claim on `public.json`: a template is
    /// still literally JSON and still opens in TextEdit, but Kapture does not
    /// become the system's handler for every JSON file on the machine
    /// (ADR-017).
    ///
    /// `exportedAs` requires the declaration to be in the bundle and fails
    /// loudly without it. That is the right failure: a quiet fallback to a
    /// dynamic type gives a save panel that works and a double-click that does
    /// not, which is the hardest version of this bug to find.
    static let kaptureTemplate = UTType(
        exportedAs: "com.eriklarson.kapture.template", conformingTo: .json
    )
}

/// What the editor is opened on.
///
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

    /// Writes the shown strip's layout out as a template and keeps a copy.
    ///
    /// The strip's own overrides are baked in, which is the point: the file is
    /// what the paper currently looks like, not what the template it started
    /// from looks like. The strip is not touched — its overrides stay exactly
    /// where they are, and the new template is a separate thing that merely
    /// begins life looking the same.
    ///
    /// The file is written and the template is installed. Writing a file the
    /// user then has to import by hand would be a step with no purpose.
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

    /// Asks for a template file and takes it in.
    ///
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

    /// Takes a template file in, if it survives `TemplateImport.decode`.
    ///
    /// A file carrying an id already in the list replaces that template, which
    /// is what makes a template editable in a text editor. Replacing one
    /// re-renders every strip that names it, so the count says so rather than
    /// letting the user find out later.
    ///
    /// Split from the panel so a file double-clicked in Finder arrives by the
    /// same path, through the same validator, with the same report.
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

    /// Drops a user template, unless a strip still names it.
    ///
    /// Nothing reference-counts a template, so this is the check that stands
    /// between a tidy-up and a strip that cannot render. Same reasoning
    /// ADR-011 applied to frames, one directory over.
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

    /// Opens the editor on the selected template.
    ///
    /// A built-in is duplicated first. A shipped layout is a constant in the
    /// binary, and redefining `classic-strip` would move every strip ever shot
    /// with it — which is the same reason `TemplateImport` refuses its id in a
    /// file.
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

    /// Writes an edited template back under its own id.
    ///
    /// A shown strip that names it is re-rendered here. A template edit changes
    /// what a recipe *means* rather than what it says, so nothing in `restyle`
    /// would notice and the viewport would sit on a stale image.
    func applyEdit(_ edit: TemplateEdit) async {
        do {
            try templateStore.install(edit.template)
            reloadTemplates()
            let name = "\u{201C}\(edit.template.name)\u{201D}"

            if edit.isCopy {
                // The user asked to edit something. Leaving them on the
                // built-in would make the whole sheet a silent no-op, so this
                // is the one place a template action moves the selection — and
                // only when the shown strip can actually go in it.
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

    /// How many stored strips name this template. A listing that cannot be
    /// read counts as none: this gates a removal, and refusing to tidy up
    /// because the directory is unreadable would be the wrong failure.
    func stripsUsing(_ id: String) -> Int {
        ((try? store.listRecipes()) ?? []).filter { $0.templateID == id }.count
    }
}
