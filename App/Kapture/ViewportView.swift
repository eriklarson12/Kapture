import KaptureKit
import SwiftUI

/// The only region that ever shows an image: the live feed during a run, the
/// shot just taken during a review beat, and the finished strip after.
struct ViewportView: View {
    let model: BoothModel

    var body: some View {
        ZStack {
            // Pure black, not a shell grey, so nothing in the window biases the
            // image. docs/design-system.md.
            Color.black

            content

            if let countdown {
                CountdownOverlay(value: countdown)
            }
            FlashOverlay(isFlashing: isFlashing)
        }
        .overlay(alignment: .top) { progress }
        .overlay(alignment: .bottom) { controls }
        .overlay(alignment: .center) { failure }
        .task { await model.startCamera() }
        .onDisappear { model.stopCamera() }
    }

    @ViewBuilder
    private var content: some View {
        if let strip = model.strip {
            StripPreviewView(image: strip.image)
        } else if let reviewing {
            // Mirrored to match the preview. The subject just saw themselves
            // one way round; the review beat must not flip them.
            Image(decorative: reviewing, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .scaleEffect(x: -1, y: 1)
                .clipped()
        } else {
            feed
        }
    }

    @ViewBuilder
    private var feed: some View {
        switch model.cameraStatus {
        case .starting:
            ProgressView()
                .controlSize(.small)
        case .live:
            CameraPreview(session: model.camera.session)
        case .failed(let message):
            notice(title: "Camera unavailable", detail: message)
        }
    }

    /// Camera and export failures are shown as text, never swallowed.
    /// docs/conventions.md.
    private func notice(title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Text(detail)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.65))
                .frame(maxWidth: 320)
        }
        .foregroundStyle(.white)
        .padding()
    }

    // MARK: - Run state

    private var countdown: Int? {
        if case .countingDown(_, let secondsRemaining) = model.runner.state {
            return secondsRemaining
        }
        return nil
    }

    private var isFlashing: Bool {
        if case .flashing = model.runner.state { return true }
        return false
    }

    private var reviewing: CGImage? {
        guard case .reviewing(let index) = model.runner.state,
              index < model.runner.frames.count else { return nil }
        return model.runner.frames[index].image
    }

    private var shotNumber: Int? {
        switch model.runner.state {
        case .countingDown(let frame, _), .flashing(let frame), .reviewing(let frame):
            frame + 1
        default:
            nil
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private var failure: some View {
        if let errorMessage = model.errorMessage {
            notice(title: "Something went wrong", detail: errorMessage)
                .background(.black.opacity(0.75))
                .onTapGesture { model.errorMessage = nil }
        }
    }

    @ViewBuilder
    private var progress: some View {
        if let shotNumber {
            Text("\(shotNumber) of \(model.sequence.frameCount)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 20)
                .accessibilityLabel("Shot \(shotNumber) of \(model.sequence.frameCount)")
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if model.strip != nil {
                Button("Retake") { model.retake() }
                    .frame(minWidth: 110, minHeight: 44)
                    .keyboardShortcut(.escape, modifiers: [])

                Button(model.isExporting ? "Saving" : "Save PNG") {
                    Task { await model.exportStrip() }
                }
                .frame(minWidth: 110, minHeight: 44)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(model.isExporting)
            } else {
                Button(shutterLabel) { Task { await model.capture() } }
                    .frame(minWidth: 160, minHeight: 44)
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(!model.canCapture)
            }
        }
        .padding(.bottom, 24)
    }

    private var shutterLabel: String {
        if model.isBuilding { return "Building strip" }
        if model.isRunning { return "Hold still" }
        return "Take \(model.sequence.frameCount) photos"
    }
}
