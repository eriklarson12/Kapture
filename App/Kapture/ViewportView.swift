import KaptureKit
import SwiftUI

/// The camera feed, the countdown, and the flash.
///
/// The single-shot path here exists to exercise 1.1 through 1.3 end to end.
/// Driving a full N-shot run is item 1.4 and belongs in a sequence driver, not
/// in a view.
struct ViewportView: View {
    let camera: AVFoundationCamera
    let template: StripTemplate
    let sequence: CaptureSequence

    enum Status: Equatable {
        case starting
        case live
        case failed(String)
    }

    @State private var status: Status = .starting
    @State private var countdown: Int?
    @State private var isFlashing = false
    @State private var isCapturing = false
    @State private var lastCapture: CGImage?

    var body: some View {
        ZStack {
            // Pure black, not a shell grey, so nothing in the window biases the
            // image. docs/design-system.md.
            Color.black

            feed

            if let countdown {
                CountdownOverlay(value: countdown)
            }
            FlashOverlay(isFlashing: isFlashing)
        }
        .overlay(alignment: .topTrailing) { lastCaptureThumbnail }
        .overlay(alignment: .bottom) { shutter }
        .task { await startCamera() }
        .onDisappear { camera.stop() }
    }

    @ViewBuilder
    private var feed: some View {
        switch status {
        case .starting:
            ProgressView()
                .controlSize(.small)
        case .live:
            CameraPreview(session: camera.session)
        case .failed(let message):
            VStack(spacing: 8) {
                Text("Camera unavailable")
                    .font(.system(size: 13, weight: .medium))
                Text(message)
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 320)
            }
            .foregroundStyle(.white)
            .padding()
        }
    }

    @ViewBuilder
    private var lastCaptureThumbnail: some View {
        if let lastCapture {
            Image(decorative: lastCapture, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 96, height: 72)
                .clipped()
                .padding(12)
                .accessibilityLabel("Most recent capture")
        }
    }

    private var shutter: some View {
        Button {
            Task { await captureOnce() }
        } label: {
            Text(isCapturing ? "Capturing" : "Take photo")
                .frame(minWidth: 120, minHeight: 44)
        }
        .disabled(status != .live || isCapturing)
        .keyboardShortcut(.space, modifiers: [])
        .padding(.bottom, 24)
    }

    private func startCamera() async {
        do {
            try await camera.start()
            status = .live
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func captureOnce() async {
        isCapturing = true
        defer { isCapturing = false }

        for remaining in stride(from: sequence.countdownSeconds, through: 1, by: -1) {
            countdown = remaining
            try? await Task.sleep(for: .seconds(1))
        }
        countdown = nil

        isFlashing = true
        try? await Task.sleep(for: FlashOverlay.duration)
        isFlashing = false

        do {
            lastCapture = try await camera.captureStill()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
