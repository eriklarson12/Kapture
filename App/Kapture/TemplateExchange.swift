import AppKit
import KaptureKit
import UniformTypeIdentifiers

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
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(source.name) Copy.json"
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

    /// Takes a template file in, if it survives `TemplateImport.decode`.
    ///
    /// A file carrying an id already in the list replaces that template, which
    /// is what makes a template editable in a text editor. Replacing one
    /// re-renders every strip that names it, so the count says so rather than
    /// letting the user find out later.
    func importTemplate() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Kapture template file."
        guard await panel.begin() == .OK, let url = panel.url else { return }

        do {
            let template = try TemplateImport.decode(try Data(contentsOf: url))
            let outcome = try templateStore.install(template)
            reloadTemplates()
            let affected = Self.stripCount(usingTemplate: template.id, in: store)
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
            let inUse = Self.stripCount(usingTemplate: template.id, in: store)
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

    /// How many stored strips name this template. A listing that cannot be
    /// read counts as none: this gates a removal, and refusing to tidy up
    /// because the directory is unreadable would be the wrong failure.
    private static func stripCount(usingTemplate id: String, in store: StripStore) -> Int {
        ((try? store.listRecipes()) ?? []).filter { $0.templateID == id }.count
    }
}
