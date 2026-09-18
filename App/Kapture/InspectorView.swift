import KaptureKit
import SwiftUI

/// Template, filter, and sequence controls. Every control here edits a value
/// that lives in the recipe, never the stored frames.
struct InspectorView: View {
    @Binding var template: StripTemplate
    @Binding var sequence: CaptureSequence

    var body: some View {
        Form {
            Section("Layout") {
                Picker("Template", selection: $template.id) {
                    ForEach(BuiltInTemplates.all) { option in
                        Text(option.name).tag(option.id)
                    }
                }
            }
            Section("Sequence") {
                Stepper("Shots: \(sequence.frameCount)", value: $sequence.frameCount, in: 1...6)
                Stepper("Countdown: \(sequence.countdownSeconds)s", value: $sequence.countdownSeconds, in: 0...10)
            }
        }
        .formStyle(.grouped)
        // TODO 2.x: filter picker, border colour, caption field.
    }
}
