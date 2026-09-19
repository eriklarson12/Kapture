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
        // The retake branch comes first on purpose. A strip exists during a
        // retake, and if it won the subject would be posing at a photograph of
        // themselves instead of at the camera.
        if model.retakingFrame != nil {
            feed
        } else if let strip = model.strip {
            StripPreviewView(image: strip.image)
        } else if let reviewing {
            // Mirrored to match the preview. The subject just saw themselves
            // one way round; the review beat must not flip them.
            Image(decorative: reviewing, scale: 1)
                .resizable()
                .scaledToFill()
                .scaleEffect(x: -1, y: 1)
                .modifier(PhotoFraming(aspect: model.template.photoAspect))
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
                .modifier(PhotoFraming(aspect: model.template.photoAspect))
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

    @ViewBuilder
    private var controls: some View {
        // Nothing to press mid-retake: the camera is busy and the strip on disk
        // is about to change under any button here.
        if model.retakingFrame == nil {
            HStack(spacing: 12) {
                if let strip = model.strip {
                    Button("Retake") { model.retake() }
                        .frame(minWidth: 110, minHeight: 44)
                        .keyboardShortcut(.escape, modifiers: [])

                    redo(shots: strip.recipe.frameIDs.count)

                    // A split button rather than one per format: PNG keeps the
                    // click and Cmd-S it has always had. The rule separates the
                    // formats that write a file from the two that do not.
                    Menu(saveLabel) {
                        Button("Animated GIF\u{2026}") { Task { await model.exportGIF() } }
                        Button("Movie\u{2026}") { Task { await model.exportMovie() } }
                        Button("PDF\u{2026}") { Task { await model.exportPDF() } }
                        Divider()
                        Button(model.didCopy ? "Copied" : "Copy Strip") {
                            Task { await model.copyStrip() }
                        }
                        Button("Print\u{2026}") { Task { await model.printStrip() } }
                    } primaryAction: {
                        Task { await model.exportStrip() }
                    }
                    .menuStyle(.button)
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
    }

    /// Re-shoot one photo without redoing the run. Numbered rather than named,
    /// because the numbers are the same ones the progress counter shows during
    /// a run, so the label is already learned by the time it is needed.
    private func redo(shots: Int) -> some View {
        HStack(spacing: 6) {
            Text("Redo")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
            ForEach(0..<shots, id: \.self) { index in
                Button("\(index + 1)") {
                    Task { await model.retakeFrame(index) }
                }
                .frame(minWidth: 32, minHeight: 28)
                .accessibilityLabel("Redo shot \(index + 1)")
            }
        }
        .monospacedDigit()
        .disabled(!model.canCapture)
    }

    private var saveLabel: String {
        if model.didCopy { return "Copied" }
        return model.isExporting ? "Saving" : "Save"
    }

    private var shutterLabel: String {
        if model.isBuilding { return "Building strip" }
        if model.isRunning { return "Hold still" }
        return "Take \(model.sequence.frameCount) photos"
    }
}

/// Constrains a live region to the aspect each photo is cropped to.
///
/// Without this the feed fills the window while the strip crops to
/// `photoAspect`, so the subject composes against one rectangle and gets
/// another, losing roughly a fifth of the width with nothing on screen to
/// warn them. Letterboxing on black is the whole fix: what is visible is
/// exactly what reaches the strip.
///
/// The empty `Color` is what makes the box real. Applying `.aspectRatio` to a
/// filling image instead measures the image, which reports a size larger than
/// it was offered, and the region ends up neither the right shape nor clipped
/// where it claims to be. A flexible view takes the ratio exactly; the content
/// then overflows into it and is cut here, once, for every live region.
private struct PhotoFraming: ViewModifier {
    let aspect: CGFloat

    func body(content: Content) -> some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay { content }
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
