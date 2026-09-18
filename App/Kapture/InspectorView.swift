import KaptureKit
import SwiftUI

/// Template and sequence controls. Every control here edits a value that lives
/// in the recipe or the timing plan, never the stored frames.
struct InspectorView: View {
    @Bindable var model: BoothModel

    var body: some View {
        Form {
            Section("Layout") {
                Picker("Template", selection: $model.templateID) {
                    ForEach(BuiltInTemplates.all) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                LabeledContent("Shots", value: "\(model.template.frameCount)")
                LabeledContent("Print size", value: printSize)
            }
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
        // TODO 2.x: filter picker, border colour, caption field.
    }

    private var printSize: String {
        let size = model.template.canvasSize
        return "\(Int(size.width / 72))x\(Int(size.height / 72)) in"
    }
}
