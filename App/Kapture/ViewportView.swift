import KaptureKit
import SwiftUI

/// The only region that ever shows an image: the live feed during a run, the
/// shot just taken during a review beat, and the finished strip after.
struct ViewportView: View {
    let model: BoothModel
    @FocusState private var hasKeys: Bool

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
        .overlay(alignment: .bottom) { model.isKiosk ? AnyView(hint) : AnyView(controls) }
        .overlay(alignment: .bottomTrailing) { shareCode }
        .overlay(alignment: .center) { message }
        .task { await model.startCamera() }
        .onDisappear { model.stopCamera() }
        // Kiosk has no buttons, so it has no keyboard shortcuts either: the
        // keys are handled here, and only while the view holds focus.
        .focusable(model.isKiosk)
        .focusEffectDisabled()
        .focused($hasKeys)
        .onChange(of: model.isKiosk, initial: true) { _, kiosk in hasKeys = kiosk }
        .onKeyPress(.space) {
            guard model.isKiosk, model.canCapture else { return .ignored }
            model.startQueue()
            return .handled
        }
        // Escape means "stop the current thing" everywhere else in macOS, so a
        // run in progress is what it stops first. Kiosk is what it stops next.
        .onKeyPress(.escape) {
            guard model.isKiosk else { return .ignored }
            // A run and a hold are both "the current thing". Kiosk is what is
            // left to stop once neither is happening.
            if model.isRunning || model.isHolding {
                model.stopQueue()
            } else {
                model.isKiosk = false
            }
            return .handled
        }
    }

    @ViewBuilder
    private var content: some View {
        // Retake comes first on purpose: a strip exists during a retake, and if
        // it won the subject would be posing at a photograph, not the camera.
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
            preview
                .modifier(PhotoFraming(aspect: model.template.photoAspect))
        case .failed(let message):
            notice(title: "Camera unavailable", detail: message)
        }
    }

    @ViewBuilder
    private var preview: some View {
        #if DEBUG
        if let demo = model.camera as? DemoCamera {
            DemoPreview(camera: demo)
        } else if let camera = model.camera as? AVFoundationCamera {
            CameraPreview(session: camera.session)
        }
        #else
        CameraPreview(session: model.camera.session)
        #endif
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

    /// One panel for both channels. A failure wins when both are set, because
    /// the thing that did not work is the thing that needs reading.
    @ViewBuilder
    private var message: some View {
        if let errorMessage = model.errorMessage {
            notice(title: "Something went wrong", detail: errorMessage)
                .background(.black.opacity(0.75))
                .onTapGesture { model.errorMessage = nil }
        } else if let text = model.notice {
            notice(title: "Done", detail: text)
                .background(.black.opacity(0.75))
                .onTapGesture { model.notice = nil }
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

    /// The only chrome kiosk mode keeps: one dim line naming the keys, gone
    /// while the run it would interrupt is happening. Carries the hold count too.
    @ViewBuilder
    private var hint: some View {
        if let seconds = model.restart.secondsRemaining {
            // Brighter and larger than the legend below: this one is a deadline,
            // not a list of keys.
            Text("Next in \(seconds)s   \u{00B7}   Space to go now   \u{00B7}   Esc to stop")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 24)
        } else if !model.isRunning && !model.isBuilding {
            Text(model.strip == nil
                ? "Space to start   \u{00B7}   Esc to leave"
                : "Space for another   \u{00B7}   \u{2318}S to save   \u{00B7}   Esc to leave")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.bottom, 24)
        }
    }

    /// Kiosk only: outside it the run controls are along this edge and the
    /// inspector already shows a smaller one.
    @ViewBuilder
    private var shareCode: some View {
        if model.isKiosk, model.isSharing, model.strip != nil,
           model.retakingFrame == nil, let code = model.shareQR {
            VStack(spacing: 8) {
                // Nearest-neighbour: a module blurred into grey is a module a
                // camera has to guess at.
                Image(decorative: code, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 160, height: 160)
                Text("Scan for your photos")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(24)
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
                    // click and Cmd-S it has always had.
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

    /// Numbered rather than named: the numbers match the progress counter shown
    /// during a run, so the label is already learned by the time it's needed.
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

/// The empty `Color` makes the box real: `.aspectRatio` on a filling image
/// instead measures a size larger than what was offered, and the clip does nothing.
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
