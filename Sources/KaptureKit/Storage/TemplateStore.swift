import Foundation

public enum TemplateStoreError: Error, Equatable {
    case notFound(String)
}

/// Whether an install displaced a template already there.
public enum TemplateInstall: Equatable {
    case added
    case replaced
}

/// User templates on disk, one JSON file each, beside the strips (ADR-014).
///
/// ```
/// <root>/Templates/<template-id>.json
/// ```
///
/// A template is referenced by a recipe, never copied into it, which is what
/// keeps a template edit able to move every strip that used it. The cost is
/// that a template file is load-bearing: delete one and the strips naming it
/// stop rendering.
///
/// `root` is injected the same way `StripStore`'s is: the app passes
/// Application Support, tests pass a temporary directory.
public struct TemplateStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var templatesURL: URL {
        root.appending(path: "Templates", directoryHint: .isDirectory)
    }

    public func fileURL(for id: String) -> URL {
        templatesURL.appending(path: "\(id).json")
    }

    /// Every user template, by name. A file that fails to decode or to
    /// validate is skipped rather than fatal — one bad template must not hide
    /// the rest, which is the rule `listRecipes()` already applies to packages.
    ///
    /// A root with no `Templates/` directory is a fresh install, not an error.
    public func load() throws -> [StripTemplate] {
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(
            at: templatesURL, includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? TemplateImport.decode(data)
            }
            // Ties break on id so the order is total; two templates may
            // genuinely share a name, and an arbitrary order for equal keys is
            // a flake waiting for a fast machine.
            .sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
    }

    /// Validates, then writes. `TemplateImport.encode` is what validates, so a
    /// caller cannot install something the importer would have refused.
    @discardableResult
    public func install(_ template: StripTemplate) throws -> TemplateInstall {
        let data = try TemplateImport.encode(template)
        try FileManager.default.createDirectory(
            at: templatesURL, withIntermediateDirectories: true
        )
        let url = fileURL(for: template.id)
        let existed = FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        // One small file needs no staging directory of its own; `.atomic`
        // already writes aside and renames.
        try data.write(to: url, options: .atomic)
        return existed ? .replaced : .added
    }

    public func remove(id: String) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw TemplateStoreError.notFound(id)
        }
        try FileManager.default.removeItem(at: url)
    }

    /// The built-ins plus these, in one dictionary. This is the lookup
    /// `RecipeRenderer` takes; there is no second path, and a user template
    /// cannot shadow a built-in because `TemplateImport` refuses a built-in id.
    ///
    /// Static, so a caller holding the templates it already loaded merges them
    /// the same way rather than writing the rule a second time. The app holds
    /// them: reading four files to render a preview would be absurd.
    public static func catalogue(with userTemplates: [StripTemplate]) -> [String: StripTemplate] {
        var merged = BuiltInTemplates.byID
        for template in userTemplates { merged[template.id] = template }
        return merged
    }

    /// The catalogue as it stands on disk.
    public func catalogue() throws -> [String: StripTemplate] {
        Self.catalogue(with: try load())
    }
}
