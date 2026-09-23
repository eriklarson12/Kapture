import CoreGraphics
import Foundation

/// Why a template file was refused. Conforms to `LocalizedError` because these
/// are read by a person standing in front of a failed import, not by a `catch`.
public enum TemplateImportError: Error, Equatable {
    case unreadable(String)
    case invalidID(String)
    /// The id of a built-in. A file must never redefine one.
    case reservedID(String)
    case missingName
    case frameCount(Int)
    /// Not positive, or does not divide the shot count evenly.
    case columns(Int)
    case canvasSize(CGSize)
    /// A measurement that cannot be negative and is: border, gutter, footer,
    /// corner radius.
    case negativeMetric(String)
    case captionFontSize(CGFloat)
    /// An asset id names a file inside one strip's package (ADR-012), so a
    /// template carrying one points at a picture that does not exist.
    case imageBackground
    /// The chrome eats the canvas and there is no room left for the photos.
    case noRoomForPhotos
}

extension TemplateImportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unreadable(let detail):
            "That file is not a Kapture template. \(detail)"
        case .invalidID(let id):
            "\"\(id)\" is not a usable template id. Use letters, digits, hyphens and underscores."
        case .reservedID(let id):
            "\"\(id)\" is a built-in template. Give the file a different id to import it alongside."
        case .missingName:
            "The template has no name."
        case .frameCount(let count):
            "A template holds between 1 and \(TemplateImport.frameCountLimit) photos, not \(count)."
        case .columns(let columns):
            columns > 0
                ? "A grid \(columns) across cannot hold the photos evenly. "
                    + "Use a column count that divides the number of shots."
                : "A template needs at least one column."
        case .canvasSize(let size):
            "\(Int(size.width))x\(Int(size.height)) points is not a printable page. "
                + "Sides run from 1 to \(Int(TemplateImport.canvasLimit)) points."
        case .negativeMetric(let name):
            "The \(name) cannot be negative."
        case .captionFontSize(let size):
            "A caption of \(Int(size))pt is outside the range "
                + "\(Int(TemplateImport.captionSizeRange.lowerBound)) to "
                + "\(Int(TemplateImport.captionSizeRange.upperBound))pt."
        case .imageBackground:
            "A template cannot carry a picture background. The picture belongs to one strip."
        case .noRoomForPhotos:
            "The border, gutter and footer leave no room for the photos."
        }
    }
}

/// A template as a file. `decode` is the only way one enters the app, and
/// `encode` refuses to write one it would not read back, so import and export can't disagree.
public enum TemplateImport {
    /// 20 inches. Larger than any paper a desktop printer takes, which is the
    /// point: this is a guard against a typo, not a policy about paper.
    public static let canvasLimit: CGFloat = 1440
    /// Enough for a long strip. A run of 13 shots is a typo, and the countdown
    /// would take five minutes.
    public static let frameCountLimit = 12
    public static let captionSizeRange: ClosedRange<CGFloat> = 4...48

    public static func encode(_ template: StripTemplate) throws -> Data {
        try validate(template)
        return try RecipeCoding.encoder().encode(template)
    }

    public static func decode(_ data: Data) throws -> StripTemplate {
        let template: StripTemplate
        do {
            template = try RecipeCoding.decoder().decode(StripTemplate.self, from: data)
        } catch let error as DecodingError {
            throw TemplateImportError.unreadable(describe(error))
        } catch {
            throw TemplateImportError.unreadable(error.localizedDescription)
        }
        try validate(template)
        return template
    }

    /// Every rule, in one order, so import and save refuse a file the same way.
    /// `isValid` alone isn't enough — a negative gutter still passes it.
    public static func validate(_ template: StripTemplate) throws {
        guard !template.id.isEmpty, template.id.allSatisfy(isIDCharacter) else {
            throw TemplateImportError.invalidID(template.id)
        }
        guard BuiltInTemplates.byID[template.id] == nil else {
            throw TemplateImportError.reservedID(template.id)
        }
        guard !template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TemplateImportError.missingName
        }
        guard (1...frameCountLimit).contains(template.frameCount) else {
            throw TemplateImportError.frameCount(template.frameCount)
        }
        guard template.columns > 0, template.frameCount % template.columns == 0 else {
            throw TemplateImportError.columns(template.columns)
        }
        let size = template.canvasSize
        guard size.width > 0, size.height > 0,
              size.width <= canvasLimit, size.height <= canvasLimit
        else {
            throw TemplateImportError.canvasSize(size)
        }
        for (name, value) in [
            ("border", template.outerInset),
            ("gutter", template.gutter),
            ("footer", template.footerHeight),
            ("corner radius", template.cornerRadius),
        ] where value < 0 {
            throw TemplateImportError.negativeMetric(name)
        }
        guard captionSizeRange.contains(template.captionFontSize) else {
            throw TemplateImportError.captionFontSize(template.captionFontSize)
        }
        if case .image = template.background {
            throw TemplateImportError.imageBackground
        }
        guard template.isValid else { throw TemplateImportError.noRoomForPhotos }
    }

    /// Names the field that went wrong. `DecodingError.localizedDescription`
    /// says only "the data couldn't be read because it is missing" — no help to someone editing in TextEdit.
    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            "It has no \"\(key.stringValue)\"."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            context.codingPath.last.map { "\"\($0.stringValue)\" is the wrong kind of value." }
                ?? "A value is the wrong kind."
        case .dataCorrupted(let context):
            context.codingPath.last.map { "\"\($0.stringValue)\" cannot be read." }
                ?? "It is not valid JSON."
        @unknown default:
            "It is not laid out like a template."
        }
    }

    /// The id is the filename, so it is restricted to what a filename can hold
    /// everywhere rather than to what this filesystem happens to tolerate.
    private static func isIDCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber
            || character == "-" || character == "_")
    }
}
