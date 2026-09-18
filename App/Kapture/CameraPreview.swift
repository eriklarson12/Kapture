import AVFoundation
import SwiftUI

/// Hosts an `AVCaptureVideoPreviewLayer`. The preview is **always mirrored**,
/// because people expect to see themselves as they do in a mirror; whether the
/// saved photo mirrors is a separate setting on the recipe.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.attach(session: session)
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.attach(session: session)
    }
}

/// Layer-backed so the preview layer is the view's own backing layer rather
/// than a sublayer that has to be resized by hand.
final class PreviewView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used; this view is created in code.")
    }

    func attach(session: AVCaptureSession) {
        if let previewLayer, previewLayer.session === session { return }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        if let existing = previewLayer {
            self.layer?.replaceSublayer(existing, with: layer)
        } else {
            self.layer?.addSublayer(layer)
        }
        previewLayer = layer
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}
