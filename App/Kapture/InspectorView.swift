import KaptureKit
import SwiftUI

/// Template and sequence controls. Every control here edits a value that lives
/// in the recipe or the timing plan, never the stored frames.
///
/// Appearance and caption controls need a recipe to edit, so they stay disabled
/// until the first strip exists. Layout and sequence configure the *next* run
/// and are live before it.
struct InspectorView: View {
    @Bindable var model: BoothModel

    var body: some View {
        Form {
            Section("Layout") {
                Picker("Template", selection: templateSelection) {
                    ForEach(model.availableTemplates) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                if model.availableTemplates.count < BuiltInTemplates.all.count {
                    Text("Only templates that hold \(shotCount) photos can show this strip.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Shots", value: "\(model.template.frameCount)")
                LabeledContent("Print size", value: printSize)
            }

            Section("Appearance") {
                ColorPicker("Paper", selection: paper, supportsOpacity: false)
                ColorPicker("Ink", selection: ink, supportsOpacity: false)
                Stepper(
                    "Border: \(Int(model.shownTemplate.outerInset))pt",
                    value: border,
                    in: 0...32,
                    step: 2
                )
                Stepper(
                    "Corners: \(Int(model.shownTemplate.cornerRadius))pt",
                    value: corners,
                    in: 0...12
                )
                if model.strip?.recipe.style != nil {
                    Button("Reset to template") { setStyle { $0 = StripStyle() } }
                }
            }
            .disabled(model.strip == nil)

            Section("Caption") {
                TextField("Caption", text: caption, prompt: Text("None"))
                Button("Insert date") { insertDate() }
                Picker("Align", selection: alignment) {
                    ForEach(CaptionAlignment.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Stepper(
                    "Size: \(Int(model.shownTemplate.captionFontSize))pt",
                    value: captionSize,
                    in: 6...16
                )
            }
            .disabled(model.strip == nil)

            Section("Sequence") {
                Stepper(
                    "Countdown: \(model.sequence.countdownSeconds)s",
                    value: $model.sequence.countdownSeconds,
                    in: 0...10
                )
                Stepper(
                    "Review: \(model.sequence.reviewSeconds, specifier: "%.1f")s",
                    value: $model.sequence.reviewSeconds,
                    in: 0...5,
                    step: 0.5
                )
            }
        }
        .formStyle(.grouped)
        .monospacedDigit()
        .disabled(model.isRunning)
        // TODO 2.4: filter picker.
    }

    // MARK: - Bindings

    /// Every appearance edit goes through here: materialize a style, change one
    /// field, and drop it again when nothing is overridden, so a strip that
    /// follows its template stores no style at all.
    private func setStyle(_ apply: @escaping (inout StripStyle) -> Void) {
        Task {
            await model.restyle { recipe in
                var style = recipe.style ?? StripStyle()
                apply(&style)
                recipe.style = style.isEmpty ? nil : style
            }
        }
    }

    private var templateSelection: Binding<String> {
        Binding(
            get: { model.templateID },
            set: { id in Task { await model.selectTemplate(id) } }
        )
    }

    private var paper: Binding<Color> {
        Binding(
            get: { model.shownTemplate.background.color },
            set: { value in setStyle { $0.background = RGBA(value) } }
        )
    }

    private var ink: Binding<Color> {
        Binding(
            get: { model.shownTemplate.foreground.color },
            set: { value in setStyle { $0.foreground = RGBA(value) } }
        )
    }

    private var border: Binding<CGFloat> {
        Binding(
            get: { model.shownTemplate.outerInset },
            set: { value in setStyle { $0.outerInset = value } }
        )
    }

    private var corners: Binding<CGFloat> {
        Binding(
            get: { model.shownTemplate.cornerRadius },
            set: { value in setStyle { $0.cornerRadius = value } }
        )
    }

    private var captionSize: Binding<CGFloat> {
        Binding(
            get: { model.shownTemplate.captionFontSize },
            set: { value in setStyle { $0.captionFontSize = value } }
        )
    }

    private var alignment: Binding<CaptionAlignment> {
        Binding(
            get: { model.shownTemplate.captionAlignment },
            set: { value in setStyle { $0.captionAlignment = value } }
        )
    }

    private var caption: Binding<String> {
        Binding(
            get: { model.strip?.recipe.caption ?? "" },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await model.restyle { $0.caption = trimmed.isEmpty ? nil : text } }
            }
        )
    }

    /// Writes the strip's own date into the caption field. It is ordinary text
    /// from that moment on, so there is one field and one rendering rule.
    private func insertDate() {
        guard let createdAt = model.strip?.recipe.createdAt else { return }
        let text = Self.dateFormatter.string(from: createdAt)
        Task { await model.restyle { $0.caption = text } }
    }

    // MARK: - Display

    private var shotCount: Int {
        model.strip?.recipe.frameIDs.count ?? model.template.frameCount
    }

    private var printSize: String {
        let size = model.shownTemplate.canvasSize
        return "\(Int(size.width / 72))x\(Int(size.height / 72)) in"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
