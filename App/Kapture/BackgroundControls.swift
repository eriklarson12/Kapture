import AppKit
import ImageIO
import KaptureKit
import SwiftUI
import UniformTypeIdentifiers

/// The background row of the Appearance section: solid, gradient, or a picture
/// the user chose.
///
/// Its own file because it is the one control in the inspector with more than
/// one shape, and because picking a file is a side effect the rest of the form
/// does not have.
struct BackgroundControls: View {
    let background: StripBackground
    let onChange: (StripBackground) -> Void
    let onChooseImage: (CGImage) -> Void

    var body: some View {
        Picker("Background", selection: kind) {
            ForEach(BackgroundKind.allCases, id: \.self) { option in
                Text(option.displayName).tag(option)
            }
        }

        switch background {
        case .solid:
            ColorPicker("Paper", selection: solidColor, supportsOpacity: false)

        case .linearGradient(_, _, let angle):
            ColorPicker("From", selection: gradientStart, supportsOpacity: false)
            ColorPicker("To", selection: gradientEnd, supportsOpacity: false)
            // Stepped rather than free: a gradient a degree off square reads as
            // a mistake, and the useful angles are all multiples of 15.
            Slider(value: gradientAngle, in: 0...345, step: 15) {
                Text("Angle: \(Int(angle))°")
            }

        case .image:
            Button("Choose Image…") { chooseImage() }
            Text("Copied into the strip, so moving the original cannot break it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Kind

    private enum BackgroundKind: String, CaseIterable {
        case solid, gradient, image

        var displayName: String {
            switch self {
            case .solid: "Solid"
            case .gradient: "Gradient"
            case .image: "Image"
            }
        }
    }

    private var currentKind: BackgroundKind {
        switch background {
        case .solid: .solid
        case .linearGradient: .gradient
        case .image: .image
        }
    }

    /// Switching kind keeps the colour that was already there, so moving from
    /// solid to gradient starts from what the user was looking at rather than
    /// from an unrelated default.
    private var kind: Binding<BackgroundKind> {
        Binding(
            get: { currentKind },
            set: { selected in
                guard selected != currentKind else { return }
                let seed = background.representativeColor
                switch selected {
                case .solid:
                    onChange(.solid(seed))
                case .gradient:
                    onChange(.linearGradient(from: seed, to: .ink, angle: 90))
                case .image:
                    // Nothing changes until a file is picked; an id for a file
                    // that does not exist would make the strip unrenderable.
                    chooseImage()
                }
            }
        )
    }

    // MARK: - Bindings

    private var solidColor: Binding<Color> {
        Binding(
            get: { background.representativeColor.color },
            set: { onChange(.solid(RGBA($0))) }
        )
    }

    private var gradientStart: Binding<Color> {
        Binding(
            get: { gradient.from.color },
            set: { value in
                let current = gradient
                onChange(.linearGradient(from: RGBA(value), to: current.to, angle: current.angle))
            }
        )
    }

    private var gradientEnd: Binding<Color> {
        Binding(
            get: { gradient.to.color },
            set: { value in
                let current = gradient
                onChange(.linearGradient(from: current.from, to: RGBA(value), angle: current.angle))
            }
        )
    }

    private var gradientAngle: Binding<Double> {
        Binding(
            get: { Double(gradient.angle) },
            set: { value in
                let current = gradient
                onChange(
                    .linearGradient(from: current.from, to: current.to, angle: CGFloat(value))
                )
            }
        )
    }

    private var gradient: (from: RGBA, to: RGBA, angle: CGFloat) {
        if case .linearGradient(let from, let to, let angle) = background {
            return (from, to, angle)
        }
        return (background.representativeColor, .ink, 90)
    }

    // MARK: - Picking a file

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use Image"

        guard panel.runModal() == .OK, let url = panel.url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        onChooseImage(image)
    }
}
