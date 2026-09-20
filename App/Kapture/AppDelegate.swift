import AppKit
import Observation

/// Files LaunchServices has handed the app, waiting for a window to take them.
///
/// A double-click on a template can arrive before any scene exists, so they
/// queue here rather than being dropped.
@MainActor
@Observable
final class OpenedFiles {
    private(set) var urls: [URL] = []

    func add(_ incoming: [URL]) {
        urls.append(contentsOf: incoming)
    }

    func take() -> [URL] {
        defer { urls = [] }
        return urls
    }
}

/// A SwiftUI scene is never offered a file to open; the application delegate
/// is. This exists only to catch that one message and hold it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let opened = OpenedFiles()

    func application(_ application: NSApplication, open urls: [URL]) {
        Self.opened.add(urls)
    }
}
