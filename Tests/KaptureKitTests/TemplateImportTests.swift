import CoreGraphics
import Foundation
import Testing
@testable import KaptureKit

@Suite("TemplateImport")
struct TemplateImportTests {
    /// A valid user template to spoil one field at a time.
    private func custom(
        id: String = "user-test",
        name: String = "Test",
        frameCount: Int = 4,
        columns: Int = 1,
        canvasSize: CGSize = CGSize(width: 144, height: 432),
        outerInset: CGFloat = 8,
        gutter: CGFloat = 6,
        footerHeight: CGFloat = 30,
        cornerRadius: CGFloat = 0,
        background: StripBackground = .solid(.paper),
        captionFontSize: CGFloat = 9
    ) -> StripTemplate {
        StripTemplate(
            id: id, name: name, frameCount: frameCount, columns: columns,
            canvasSize: canvasSize,
            outerInset: outerInset, gutter: gutter, footerHeight: footerHeight,
            cornerRadius: cornerRadius, background: background,
            captionFontSize: captionFontSize
        )
    }

    private func rejects(_ template: StripTemplate, _ expected: TemplateImportError) {
        #expect(throws: expected) { try TemplateImport.validate(template) }
    }

    /// What 5.1 writes is exactly what 5.2 has to read back. Built-ins go
    /// through as derived copies because their own ids are reserved.
    @Test("a template survives the round trip through a file")
    func roundTrip() throws {
        for builtIn in BuiltInTemplates.all {
            let template = builtIn.derived(name: "\(builtIn.name) Copy")
            let restored = try TemplateImport.decode(try TemplateImport.encode(template))
            #expect(restored == template)
        }
    }

    @Test("a gradient background survives the round trip")
    func roundTripGradient() throws {
        let template = custom(
            background: .linearGradient(from: .paper, to: .ink, angle: 45)
        )
        let restored = try TemplateImport.decode(try TemplateImport.encode(template))
        #expect(restored == template)
    }

    /// Someone will write one of these by hand. This is the file that says
    /// they can: only the fields the initializer has no default for.
    @Test("a hand-written file with only the required keys decodes")
    func minimalFile() throws {
        let json = """
        {
          "id": "user-minimal",
          "name": "Minimal",
          "frameCount": 3,
          "canvasSize": { "width": 144, "height": 432 },
          "outerInset": 10,
          "gutter": 8,
          "footerHeight": 24
        }
        """
        let template = try TemplateImport.decode(Data(json.utf8))
        #expect(template.frameCount == 3)
        #expect(template.columns == 1)
        #expect(template.cornerRadius == 0)
        #expect(template.foreground == .ink)
        #expect(template.background == .solid(.paper))
        #expect(template.captionFontSize == 9)
        #expect(template.captionAlignment == .center)
    }

    /// The coder is hand-written, so a field added without a line in it would
    /// round-trip as its default unnoticed. This test is the one that would notice.
    @Test("a template file holds exactly the keys the format names")
    func keysOnFile() throws {
        let data = try TemplateImport.encode(custom())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let keys = Set(object?.keys ?? [:].keys)
        #expect(keys == Set(StripTemplate.CodingKeys.allCases.map(\.rawValue)))
    }

    /// Width and height are named because `[144, 432]` in a hand-edited file
    /// is a coin flip; a transposed canvas reads as a bug in the app.
    @Test("the canvas is written with its sides named")
    func namedCanvas() throws {
        let text = String(decoding: try TemplateImport.encode(custom()), as: UTF8.self)
        #expect(text.contains("\"width\""))
        #expect(text.contains("\"height\""))
    }

    /// The shape any other Swift program hands over, since it is what `CGSize`
    /// writes for itself.
    @Test("a canvas written as a bare pair is read rather than refused")
    func barePairCanvas() throws {
        let json = """
        { "id": "user-pair", "name": "Pair", "frameCount": 4,
          "canvasSize": [144, 432],
          "outerInset": 8, "gutter": 6, "footerHeight": 30 }
        """
        let template = try TemplateImport.decode(Data(json.utf8))
        #expect(template.canvasSize == CGSize(width: 144, height: 432))
    }

    @Test("a grid survives the round trip")
    func roundTripGrid() throws {
        let template = BuiltInTemplates.gridQuad.derived(name: "Quad Copy")
        let restored = try TemplateImport.decode(try TemplateImport.encode(template))
        #expect(restored == template)
        #expect(restored.columns == 2)
    }

    /// Every template file 5.1 wrote predates the key. They all have to keep
    /// opening, as the stacks they are.
    @Test("a file written before columns existed decodes as a stack")
    func columnsDefaultOnOldFile() throws {
        let json = """
        {
          "id": "user-old",
          "name": "Old",
          "frameCount": 4,
          "canvasSize": { "width": 144, "height": 432 },
          "outerInset": 8,
          "gutter": 6,
          "footerHeight": 30,
          "cornerRadius": 0,
          "background": {
            "kind": "solid",
            "color": { "red": 1, "green": 1, "blue": 1, "alpha": 1 }
          },
          "foreground": { "red": 0, "green": 0, "blue": 0, "alpha": 1 },
          "captionFontSize": 9,
          "captionAlignment": "center"
        }
        """
        let template = try TemplateImport.decode(Data(json.utf8))
        #expect(template.columns == 1)
        #expect(template.photoRects().count == 4)
    }

    @Test("refuses bytes that are not a template")
    func garbage() {
        #expect(throws: TemplateImportError.self) {
            try TemplateImport.decode(Data("not json at all".utf8))
        }
        #expect(throws: TemplateImportError.self) {
            try TemplateImport.decode(Data("{\"id\": \"user-x\", \"name\":".utf8))
        }
    }

    /// Someone hand-editing a template needs the field, not "the data
    /// couldn't be read because it is missing," which is the decoder's default.
    @Test("a refusal names the field that went wrong")
    func namesTheField() {
        let missing = """
        { "id": "user-x", "name": "X",
          "canvasSize": { "width": 144, "height": 432 },
          "outerInset": 8, "gutter": 6, "footerHeight": 30 }
        """
        #expect(throws: TemplateImportError.unreadable("It has no \"frameCount\".")) {
            try TemplateImport.decode(Data(missing.utf8))
        }

        let wrongType = """
        { "id": "user-x", "name": "X", "frameCount": "four",
          "canvasSize": { "width": 144, "height": 432 },
          "outerInset": 8, "gutter": 6, "footerHeight": 30 }
        """
        #expect(
            throws: TemplateImportError.unreadable("\"frameCount\" is the wrong kind of value.")
        ) {
            try TemplateImport.decode(Data(wrongType.utf8))
        }
    }

    /// A recipe is the other JSON file in this project, and the one a user is
    /// most likely to pick by mistake.
    @Test("refuses a recipe offered as a template")
    func recipeIsNotATemplate() throws {
        let recipe = StripRecipe(templateID: "classic-strip", frameIDs: [UUID()])
        let data = try RecipeCoding.encoder().encode(recipe)
        #expect(throws: TemplateImportError.self) { try TemplateImport.decode(data) }
    }

    @Test("refuses a built-in id rather than shadowing it")
    func reservedID() {
        for builtIn in BuiltInTemplates.all {
            rejects(builtIn, .reservedID(builtIn.id))
        }
    }

    @Test("refuses an id that is not a filename")
    func invalidID() {
        rejects(custom(id: ""), .invalidID(""))
        rejects(custom(id: "../escape"), .invalidID("../escape"))
        rejects(custom(id: "with space"), .invalidID("with space"))
    }

    @Test("refuses a template with no name")
    func missingName() {
        rejects(custom(name: ""), .missingName)
        rejects(custom(name: "   "), .missingName)
    }

    @Test("refuses a shot count outside the range a run can hold")
    func frameCount() {
        rejects(custom(frameCount: 0), .frameCount(0))
        rejects(custom(frameCount: 13), .frameCount(13))
    }

    /// A ragged grid renders a half-empty last row, which on paper reads as a
    /// missing photo rather than as a layout.
    @Test("refuses a column count that does not divide the shots")
    func columns() {
        rejects(custom(frameCount: 4, columns: 3), .columns(3))
        rejects(custom(frameCount: 4, columns: 0), .columns(0))
        rejects(custom(frameCount: 4, columns: -2), .columns(-2))
        rejects(custom(frameCount: 5, columns: 2), .columns(2))
    }

    @Test("refuses a canvas that is not a printable page")
    func canvasSize() {
        let empty = CGSize(width: 0, height: 432)
        rejects(custom(canvasSize: empty), .canvasSize(empty))
        let huge = CGSize(width: 4000, height: 432)
        rejects(custom(canvasSize: huge), .canvasSize(huge))
    }

    /// `isValid` passes every one of these. It only asks whether the photos
    /// fit, and a negative gutter makes them fit better.
    @Test("refuses a negative measurement")
    func negativeMetrics() {
        rejects(custom(outerInset: -4), .negativeMetric("border"))
        rejects(custom(gutter: -6), .negativeMetric("gutter"))
        rejects(custom(footerHeight: -30), .negativeMetric("footer"))
        rejects(custom(cornerRadius: -2), .negativeMetric("corner radius"))
        #expect(custom(gutter: -6).isValid)
    }

    @Test("refuses a caption size nothing would print")
    func captionFontSize() {
        rejects(custom(captionFontSize: 1), .captionFontSize(1))
        rejects(custom(captionFontSize: 200), .captionFontSize(200))
    }

    /// An asset id names a file inside one strip's package (ADR-012), so a
    /// template carrying one points at a picture that does not exist.
    @Test("refuses a picture background")
    func imageBackground() {
        rejects(custom(background: .image(id: UUID())), .imageBackground)
    }

    @Test("refuses a template whose chrome leaves no room for the photos")
    func noRoomForPhotos() {
        rejects(custom(canvasSize: CGSize(width: 144, height: 40)), .noRoomForPhotos)
    }

    /// Saving is the same gate as importing, or a file could be written that
    /// could never be read back.
    @Test("saving refuses what importing would refuse")
    func encodeValidates() {
        #expect(throws: TemplateImportError.imageBackground) {
            try TemplateImport.encode(custom(background: .image(id: UUID())))
        }
    }

    @Test("every refusal carries a message for a person")
    func messages() {
        let errors: [TemplateImportError] = [
            .unreadable("x"), .invalidID("x"), .reservedID("x"), .missingName,
            .frameCount(0), .columns(3), .canvasSize(.zero), .negativeMetric("gutter"),
            .captionFontSize(1), .imageBackground, .noRoomForPhotos,
        ]
        for error in errors {
            #expect(error.localizedDescription.isEmpty == false)
            #expect(error.localizedDescription.contains("TemplateImportError") == false)
        }
    }
}
