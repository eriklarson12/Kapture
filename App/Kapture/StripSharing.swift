import CoreGraphics
import Foundation
import KaptureKit

/// One strip is shared at a time, behind a token that makes a stale link fail
/// closed rather than resolve to whoever is in front of the camera now.
extension BoothModel {
    /// Starts the listener and points it at whatever is on screen.
    func startSharing() async {
        let server = self.server ?? StripServer { [weak self] request in
            guard let self else {
                return .text(HTTPStatus.notFound.reason, status: .notFound)
            }
            return await self.respond(to: request)
        }
        self.server = server

        do {
            sharePort = try await server.start()
            shareError = nil
            isSharing = true
            if let recipe = strip?.recipe {
                share(recipe)
            } else {
                refreshLink()
            }
        } catch {
            // A sandbox missing `network.server`, or a port that won't bind — either
            // way it's text on screen, never a silent switch that does nothing.
            shareError = error.localizedDescription
            isSharing = false
        }
    }

    func stopSharing() {
        server?.stop()
        isSharing = false
        sharePort = nil
        shareToken = nil
        sharedRecipe = nil
        shareURL = nil
        shareQR = nil
    }

    /// Withdraws the previous link and mints one for this strip, called the
    /// moment the old one stops being what's on screen.
    func share(_ recipe: StripRecipe) {
        guard isSharing else { return }
        sharedRecipe = recipe.id
        shareToken = ShareToken.mint()
        refreshLink()
    }

    /// Re-read every time rather than remembered: DHCP can move a laptop mid-party,
    /// and a code carrying yesterday's address fails in a way nobody can diagnose.
    private func refreshLink() {
        guard let port = sharePort, let token = shareToken,
              let host = LocalAddress.ipv4() else {
            shareURL = nil
            shareQR = nil
            if sharePort != nil && LocalAddress.ipv4() == nil {
                shareError = "This Mac has no network address. Join a Wi-Fi network and switch sharing off and on."
            }
            return
        }

        let url = URL(string: "http://\(host):\(port)\(ShareRoute.path(for: .page(token)))")
        shareURL = url
        shareQR = url.flatMap { try? QRCode.image(for: $0.absoluteString) }
    }

    private func respond(to request: HTTPRequest) async -> HTTPResponse {
        guard let route = ShareRoute.parse(request.path) else {
            return .text(HTTPStatus.notFound.reason, status: .notFound)
        }
        // The token is the whole gate. A link for a strip that has been
        // replaced is not an error and must not read like one.
        guard route.token == shareToken, let id = sharedRecipe else {
            return .html(SharePage.gone(), status: .notFound)
        }

        do {
            let recipe = try store.load(id: id)
            switch route {
            case .page:
                return .html(SharePage.html(token: route.token, caption: recipe.caption))
            case .png:
                return HTTPResponse(contentType: "image/png", body: try await png(of: recipe))
            case .gif:
                return HTTPResponse(contentType: "image/gif", body: try await gif(of: recipe))
            }
        } catch {
            return .text("That strip could not be rendered.", status: .serverError)
        }
    }

    /// The same 300 dpi render the save panel writes, so what a phone keeps is
    /// what the Mac would have exported.
    private func png(of recipe: StripRecipe) async throws -> Data {
        let renderer = self.renderer
        let scale = try renderer.template(for: recipe).scale(forDPI: StripExport.dpi)
        return try await Task.detached(priority: .userInitiated) {
            try ImageCodec.encodePNG(renderer.render(recipe, scale: scale), dpi: StripExport.dpi)
        }.value
    }

    private func gif(of recipe: StripRecipe) async throws -> Data {
        let renderer = self.renderer
        return try await Task.detached(priority: .userInitiated) {
            let frames = try renderer.renderFrames(recipe, height: StripExport.gifHeight)
            return try ImageCodec.encodeGIF(frames, delaySeconds: StripExport.gifDelay)
        }.value
    }
}
