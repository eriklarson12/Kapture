import KaptureKit
import SwiftUI

/// Template and sequence controls. Every control here edits a value that lives
/// in the recipe or the timing plan, never the stored frames.
///
/// Appearance and caption *styling* need a recipe to edit, so they stay
/// disabled until the first strip exists. Layout, sequence and the caption text
/// configure the *next* run and are live before it.
struct InspectorView: View {
    @Bindable var model: BoothModel

    var body: some View {
        Form {
            Section("Layout") {
                HStack(spacing: 6) {
                    Picker("Template", selection: templateSelection) {
                        ForEach(model.availableTemplates) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    templateActions
                }
                if model.availableTemplates.count < model.allTemplates.count {
                    Text("Only templates that hold \(shotCount) photos can show this strip.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Shots", value: "\(model.template.frameCount)")
                LabeledContent("Print size", value: printSize)
            }

            Section("Photos") {
                Picker("Filter", selection: filter) {
                    ForEach(PhotoFilter.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Toggle("Mirror output", isOn: mirrorOutput)
                Text("The preview and the review beat are always mirrored. This is whether the strip is too.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .disabled(model.strip == nil)

            Section("Appearance") {
                BackgroundControls(
                    background: model.shownTemplate.background,
                    onChange: { value in setStyle { $0.background = value } },
                    onChooseImage: { image in
                        Task { await model.setBackgroundImage(image) }
                    }
                )
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

            // The text is live before the first strip and the styling is not:
            // a caption typed here is carried by every strip shot after it, so
            // a party is captioned once rather than once a run.
            Section("Caption") {
                TextField("Caption", text: caption, prompt: Text("None"))
                Button("Insert date") { insertDate() }
                Group {
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
                // Here rather than in a menu because this section is what a
                // run does, and because kiosk mode is configured before it is
                // entered, exactly like the template.
                Toggle("Sound", isOn: sound)
                Toggle("Auto-restart in kiosk", isOn: $model.autoRestart)
                Stepper("Hold: \(model.restart.seconds)s", value: hold, in: 5...60, step: 5)
                    .disabled(!model.autoRestart)
                Text("A queue runs in kiosk mode only. Anywhere else the timer would throw away the strip you are editing.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Sharing") {
                Toggle("Share to phones", isOn: sharing)
                if let url = model.shareURL {
                    LabeledContent("Link") {
                        Text(url.absoluteString)
                            .font(.system(size: 11))
                            .textSelection(.enabled)
                    }
                    if let code = model.shareQR {
                        // Small here and large in the viewport: this one is for
                        // the operator checking it works, not for a guest
                        // across a room.
                        Image(decorative: code, scale: 1)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 96, height: 96)
                    }
                }
                if let shareError = model.shareError {
                    Text(shareError)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text("The strip on screen is served to anyone on this Wi-Fi holding the link. One strip at a time: a link stops working when the next strip is taken, and every link dies when Kapture quits.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .monospacedDigit()
        .disabled(model.isRunning)
    }

    /// Import, save and remove, next to the list they act on rather than in
    /// the File menu: this is where someone goes to look at templates.
    private var templateActions: some View {
        Menu {
            Button("Import Template\u{2026}") { Task { await model.importTemplate() } }
            Button("Save Template\u{2026}") { Task { await model.saveTemplate() } }
                .disabled(model.strip == nil)
            // Named for what it does. Editing a built-in copies it first, and
            // a menu item that said otherwise would be lying about which
            // template the sheet is about to change.
            Button(model.canRemoveTemplate ? "Edit Template\u{2026}" : "Duplicate & Edit\u{2026}") {
                model.editTemplate()
            }
            Divider()
            Button("Remove Template") { Task { await model.removeTemplate() } }
                .disabled(!model.canRemoveTemplate)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Template actions")
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

    /// The hold is a value on the timer rather than on the model, so it is
    /// reached by hand rather than through `@Bindable`.
    private var hold: Binding<Int> {
        Binding(
            get: { model.restart.seconds },
            set: { model.restart.seconds = $0 }
        )
    }

    private var sharing: Binding<Bool> {
        Binding(
            get: { model.isSharing },
            set: { wanted in
                Task { wanted ? await model.startSharing() : model.stopSharing() }
            }
        )
    }

    private var sound: Binding<Bool> {
        Binding(
            get: { !model.sounds.isMuted },
            set: { model.sounds.isMuted = !$0 }
        )
    }

    private var filter: Binding<PhotoFilter> {
        Binding(
            get: { model.strip?.recipe.filter ?? .none },
            set: { value in Task { await model.restyle { $0.filter = value } } }
        )
    }

    private var mirrorOutput: Binding<Bool> {
        Binding(
            get: { model.strip?.recipe.mirrorOutput ?? true },
            set: { value in Task { await model.restyle { $0.mirrorOutput = value } } }
        )
    }

    private var templateSelection: Binding<String> {
        Binding(
            get: { model.templateID },
            set: { id in Task { await model.selectTemplate(id) } }
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

    /// The shown strip's own caption when there is one, and the caption the
    /// next strip will be shot with when there is not.
    private var caption: Binding<String> {
        Binding(
            get: { model.strip.map { $0.recipe.caption ?? "" } ?? model.standingCaption },
            set: { model.setCaption($0) }
        )
    }

    /// Writes the strip's own date into the caption field, or today's when
    /// there is no strip yet — which is when a party is being set up. It is
    /// ordinary text from that moment on, so there is one field and one
    /// rendering rule.
    private func insertDate() {
        let date = model.strip?.recipe.createdAt ?? Date()
        model.setCaption(Self.dateFormatter.string(from: date))
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
