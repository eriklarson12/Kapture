import Foundation

/// The one page a guest sees, built as a pure function of a token and a caption.
/// Achromatic like the app, and no script or asset — a second request fails on a slow party network.
public enum SharePage {
    /// A caption is the first user text in this project that becomes markup.
    /// Ampersand must be escaped first, or the entities after it double-escape.
    public static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    public static func html(token: ShareToken, caption: String?) -> String {
        let png = ShareRoute.path(for: .png(token))
        let gif = ShareRoute.path(for: .gif(token))
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = trimmed.flatMap { $0.isEmpty ? nil : "<p class=\"caption\">\(escaped($0))</p>" }

        return document(
            title: "Your photo strip",
            body: """
                    <img src="\(png)" alt="Your photo strip">
                    \(heading ?? "")
                    <a class="button" href="\(png)" download>Save the strip</a>
                    <a class="button" href="\(gif)" download>Save the animation</a>
                    <p class="note">On a phone, press and hold the picture to save it to your photos.</p>
                """
        )
    }

    /// What a withdrawn link says. This is the normal end of every link, not
    /// an error, so it must read like an explanation and not a fault.
    public static func gone() -> String {
        document(
            title: "That strip has gone",
            body: """
                    <p class="caption">That strip has gone.</p>
                    <p class="note">The booth shares one strip at a time, so a link stops working when the next strip is taken. Ask for a new code.</p>
                """
        )
    }

    private static func document(title: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escaped(title))</title>
        <style>
        :root { color-scheme: dark; }
        body {
          margin: 0; padding: 24px 16px 40px;
          background: #000; color: #fff;
          font: 16px/1.5 -apple-system, system-ui, sans-serif;
          text-align: center;
        }
        main { max-width: 420px; margin: 0 auto; }
        img { max-width: 100%; height: auto; border-radius: 4px; }
        .caption { font-size: 15px; color: #d8d8d8; margin: 16px 0 4px; }
        .note { font-size: 13px; color: #8a8a8a; margin-top: 20px; }
        .button {
          display: block; margin: 12px 0; padding: 14px 16px;
          background: #1c1c1c; color: #fff; text-decoration: none;
          border: 1px solid #3a3a3a; border-radius: 8px;
        }
        </style>
        </head>
        <body>
        <main>
        \(body)
        </main>
        </body>
        </html>
        """
    }
}
