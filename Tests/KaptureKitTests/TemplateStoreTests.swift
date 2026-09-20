import CoreGraphics
import Foundation
import Testing
@testable import KaptureKit

@Suite("TemplateStore")
struct TemplateStoreTests {
    private func withStore(_ body: (TemplateStore) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "KaptureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(TemplateStore(root: root))
    }

    private func custom(id: String, name: String) -> StripTemplate {
        StripTemplate(
            id: id, name: name, frameCount: 4,
            canvasSize: CGSize(width: 144, height: 432),
            outerInset: 8, gutter: 6, footerHeight: 30
        )
    }

    @Test("a fresh install has no templates and does not throw saying so")
    func emptyRoot() throws {
        try withStore { store in
            let loaded = try store.load()
            let catalogue = try store.catalogue()
            #expect(loaded.isEmpty)
            #expect(catalogue == BuiltInTemplates.byID)
        }
    }

    @Test("an installed template loads back identically")
    func roundTrip() throws {
        try withStore { store in
            let template = custom(id: "user-a", name: "Cream Wide")
            let outcome = try store.install(template)
            let loaded = try store.load()
            #expect(outcome == .added)
            #expect(loaded == [template])
        }
    }

    @Test("the catalogue is the built-ins plus the user's")
    func catalogueMerges() throws {
        try withStore { store in
            let template = custom(id: "user-a", name: "Cream Wide")
            try store.install(template)
            let catalogue = try store.catalogue()
            #expect(catalogue.count == BuiltInTemplates.all.count + 1)
            #expect(catalogue["user-a"] == template)
            #expect(catalogue[BuiltInTemplates.classicStrip.id] == BuiltInTemplates.classicStrip)
        }
    }

    /// Iterating on a template in a text editor means importing the same id
    /// over and over. One id is one file.
    @Test("installing the same id again replaces it and leaves one file")
    func replace() throws {
        try withStore { store in
            try store.install(custom(id: "user-a", name: "First"))
            let outcome = try store.install(custom(id: "user-a", name: "Second"))
            #expect(outcome == .replaced)
            let loaded = try store.load()
            #expect(loaded.count == 1)
            #expect(loaded[0].name == "Second")
        }
    }

    @Test("a built-in id cannot be installed over and writes nothing")
    func reservedID() throws {
        try withStore { store in
            #expect(throws: TemplateImportError.reservedID("classic-strip")) {
                try store.install(
                    StripTemplate(
                        id: "classic-strip", name: "Impostor", frameCount: 4,
                        canvasSize: CGSize(width: 144, height: 432),
                        outerInset: 8, gutter: 6, footerHeight: 30
                    )
                )
            }
            let loaded = try store.load()
            let catalogue = try store.catalogue()
            #expect(loaded.isEmpty)
            #expect(catalogue["classic-strip"] == BuiltInTemplates.classicStrip)
        }
    }

    @Test("an invalid template is refused before it reaches disk")
    func installValidates() throws {
        try withStore { store in
            #expect(throws: TemplateImportError.frameCount(0)) {
                try store.install(
                    StripTemplate(
                        id: "user-a", name: "Empty", frameCount: 0,
                        canvasSize: CGSize(width: 144, height: 432),
                        outerInset: 8, gutter: 6, footerHeight: 30
                    )
                )
            }
            let loaded = try store.load()
            #expect(loaded.isEmpty)
        }
    }

    /// One bad file must not hide the rest, which is the rule `listRecipes()`
    /// already applies to packages.
    @Test("a file that does not decode is skipped, not fatal")
    func corruptFileSkipped() throws {
        try withStore { store in
            try store.install(custom(id: "user-good", name: "Good"))
            try Data("{ not a template".utf8)
                .write(to: store.fileURL(for: "user-bad"))
            let loaded = try store.load()
            #expect(loaded.count == 1)
            #expect(loaded[0].id == "user-good")
        }
    }

    /// A file hand-edited into something the importer would refuse is the same
    /// case as a corrupt one: it is not a template any more.
    @Test("a file edited into an invalid template is skipped")
    func invalidFileSkipped() throws {
        try withStore { store in
            let json = """
            { "id": "user-bad", "name": "Bad", "frameCount": 0,
              "canvasSize": { "width": 144, "height": 432 },
              "outerInset": 8, "gutter": 6, "footerHeight": 30 }
            """
            try FileManager.default.createDirectory(
                at: store.templatesURL, withIntermediateDirectories: true
            )
            try Data(json.utf8).write(to: store.fileURL(for: "user-bad"))
            let loaded = try store.load()
            #expect(loaded.isEmpty)
        }
    }

    @Test("templates come back in name order, ties broken on id")
    func sortedByName() throws {
        try withStore { store in
            try store.install(custom(id: "user-c", name: "Zebra"))
            try store.install(custom(id: "user-b", name: "Apple"))
            try store.install(custom(id: "user-a", name: "Apple"))
            let loaded = try store.load()
            #expect(loaded.map(\.id) == ["user-a", "user-b", "user-c"])
        }
    }

    @Test("removing a template deletes its file")
    func remove() throws {
        try withStore { store in
            try store.install(custom(id: "user-a", name: "Cream Wide"))
            try store.remove(id: "user-a")
            let loaded = try store.load()
            #expect(loaded.isEmpty)
        }
    }

    @Test("removing a template that is not there says so")
    func removeMissing() throws {
        try withStore { store in
            #expect(throws: TemplateStoreError.notFound("user-nope")) {
                try store.remove(id: "user-nope")
            }
        }
    }
}
