import Foundation
import Testing
@testable import KaptureKit

@Suite("StripRecipe")
struct StripRecipeTests {
    @Test("round-trips a wall-clock timestamp exactly")
    func nowRoundTrips() throws {
        let recipe = StripRecipe(templateID: BuiltInTemplates.classicStrip.id, frameIDs: [UUID()])
        let data = try RecipeCoding.encoder().encode(recipe)
        #expect(try RecipeCoding.decoder().decode(StripRecipe.self, from: data) == recipe)
    }

    /// One `Date()` can survive a broken round trip by luck, which is exactly
    /// how the millisecond-rounding bug hid. Sweep instead.
    @Test("round-trips 500 arbitrary timestamps exactly")
    func manyTimestampsRoundTrip() throws {
        let encoder = RecipeCoding.encoder()
        let decoder = RecipeCoding.decoder()
        for _ in 0..<500 {
            let offset = Double.random(in: -2_000_000_000...2_000_000_000)
            let recipe = StripRecipe(
                createdAt: Date(timeIntervalSinceReferenceDate: offset),
                templateID: BuiltInTemplates.classicStrip.id,
                frameIDs: [UUID()]
            )
            let decoded = try decoder.decode(StripRecipe.self, from: encoder.encode(recipe))
            #expect(decoded == recipe, "failed at offset \(offset)")
        }
    }

    @Test("normalizing is idempotent")
    func storableIsIdempotent() {
        for _ in 0..<200 {
            let date = Date(timeIntervalSinceReferenceDate: .random(in: -2_000_000_000...2_000_000_000))
            let once = StripRecipe.storable(date)
            #expect(StripRecipe.storable(once) == once)
        }
    }

    @Test("round-trips through JSON unchanged")
    func codableRoundTrip() throws {
        let recipe = StripRecipe(
            templateID: BuiltInTemplates.classicStrip.id,
            frameIDs: [UUID(), UUID(), UUID(), UUID()],
            filter: .sepia,
            caption: "Sept 2026",
            mirrorOutput: true
        )
        let data = try RecipeCoding.encoder().encode(recipe)
        let decoded = try RecipeCoding.decoder().decode(StripRecipe.self, from: data)
        #expect(decoded == recipe)
    }

    @Test("preserves sub-second precision on createdAt")
    func timestampPrecision() throws {
        let recipe = StripRecipe(
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000.123),
            templateID: BuiltInTemplates.classicStrip.id,
            frameIDs: [UUID()]
        )
        let data = try RecipeCoding.encoder().encode(recipe)
        let decoded = try RecipeCoding.decoder().decode(StripRecipe.self, from: data)
        #expect(decoded.createdAt == recipe.createdAt)
    }

    @Test("templates round-trip so a custom template is just JSON")
    func templateRoundTrip() throws {
        for template in BuiltInTemplates.all {
            let data = try RecipeCoding.encoder().encode(template)
            #expect(try RecipeCoding.decoder().decode(StripTemplate.self, from: data) == template)
        }
    }

    @Test("resolves a built-in template by id")
    func lookup() {
        #expect(BuiltInTemplates.template(id: "classic-strip") == BuiltInTemplates.classicStrip)
        #expect(BuiltInTemplates.template(id: "nope") == nil)
    }
}
