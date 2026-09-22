import CoreGraphics
import Foundation
import Testing
@testable import KaptureKit

@Suite("StripStyle")
struct StripStyleTests {
    @Test("an absent style leaves the template untouched")
    func nilStyleIsIdentity() {
        let template = BuiltInTemplates.classicStrip
        #expect(template.applying(nil) == template)
    }

    @Test("an empty style leaves the template untouched")
    func emptyStyleIsIdentity() {
        let template = BuiltInTemplates.classicStrip
        let style = StripStyle()
        #expect(style.isEmpty)
        #expect(template.applying(style) == template)
    }

    @Test("only the fields a style sets are overridden")
    func partialOverride() {
        let template = BuiltInTemplates.classicStrip
        let style = StripStyle(background: .solid(RGBA(red: 0, green: 0, blue: 0)), outerInset: 20)
        let resolved = template.applying(style)

        #expect(resolved.background == .solid(RGBA(red: 0, green: 0, blue: 0)))
        #expect(resolved.outerInset == 20)
        // Everything else still follows the template, which is what keeps a
        // template edit able to move past strips (roadmap 4.4).
        #expect(resolved.foreground == template.foreground)
        #expect(resolved.gutter == template.gutter)
        #expect(resolved.footerHeight == template.footerHeight)
        #expect(resolved.captionAlignment == template.captionAlignment)
    }

    @Test("a plausible override still leaves room for the photos")
    func resolvedTemplateStaysValid() {
        let resolved = BuiltInTemplates.classicStrip
            .applying(StripStyle(outerInset: 16, cornerRadius: 4))
        #expect(resolved.isValid)
        // Named rather than written as `144 - 32`: literal arithmetic on the
        // right of a CGFloat comparison silently evaluates false inside #expect.
        let expectedWidth: CGFloat = 112
        #expect(resolved.photoWidth == expectedWidth)
    }

    @Test("a style is not empty once anything is set")
    func isEmptyTracksContent() {
        #expect(StripStyle(captionAlignment: .leading).isEmpty == false)
        #expect(StripStyle(cornerRadius: 0).isEmpty == false)
    }

    /// The guard for the strips already on disk: they were written before
    /// `style` existed, so their JSON has no such key and must still decode.
    @Test("a recipe written before styling existed still decodes")
    func decodesRecipeWithoutStyleKey() throws {
        let json = """
        {
          "createdAt": "2026-09-18T04:54:10.679Z",
          "filter": "none",
          "frameIDs": ["E7234365-5438-427B-BC02-EB895C11C711"],
          "id": "BD7ABB7D-0750-43EC-BFC6-4A4862D5C576",
          "mirrorOutput": false,
          "templateID": "classic-strip"
        }
        """
        let recipe = try RecipeCoding.decoder().decode(
            StripRecipe.self, from: Data(json.utf8)
        )
        #expect(recipe.style == nil)
        // The same fixture is the guard for every later optional field.
        #expect(recipe.backdrop == nil)
        #expect(recipe.templateID == "classic-strip")
    }

    @Test("a style survives a recipe round trip")
    func styleRoundTrips() throws {
        let recipe = StripRecipe(
            templateID: "classic-strip",
            frameIDs: [UUID()],
            caption: "Hello",
            style: StripStyle(foreground: .ink, outerInset: 12, captionAlignment: .trailing)
        )
        let data = try RecipeCoding.encoder().encode(recipe)
        let decoded = try RecipeCoding.decoder().decode(StripRecipe.self, from: data)
        #expect(decoded == recipe)
        #expect(decoded.style?.captionAlignment == .trailing)
        #expect(decoded.style?.cornerRadius == nil)
    }
}
