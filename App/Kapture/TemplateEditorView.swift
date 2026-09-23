import KaptureKit
import SwiftUI

/// Edits fields `StripStyle` deliberately cannot override, since they change
/// the shape of the paper, not its look. Works on a copy; Save is the single write.
struct TemplateEditorView: View {
    let model: BoothModel
    let edit: TemplateEdit

    @State private var template: StripTemplate
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    init(model: BoothModel, edit: TemplateEdit) {
        self.model = model
        self.edit = edit
        _template = State(initialValue: edit.template)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                controls
                    .frame(width: 300)
                TemplateWireframe(template: template)
                    .frame(width: 160, height: 300)
            }
            .padding(20)
            Divider()
            footer
        }
        .frame(width: 560)
        .monospacedDigit()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("Name") {
                TextField("Name", text: $template.name)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }

            slider("Shots", value: shots, in: 1...Double(TemplateImport.frameCountLimit),
                   step: 1, caption: "\(template.frameCount)")
                .disabled(edit.stripsInUse > 0)
            if edit.stripsInUse > 0 {
                note(
                    edit.stripsInUse == 1
                        ? "1 strip already uses this template, so the shot count is fixed."
                        : "\(edit.stripsInUse) strips already use this template, so the shot count is fixed."
                )
            }

            LabeledContent("Columns") {
                Picker("Columns", selection: $template.columns) {
                    ForEach(divisors, id: \.self) { Text("\($0)") }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            LabeledContent("Paper") {
                Picker("Paper", selection: paper) {
                    ForEach(papers) { option in
                        Text(option.inches).tag(option)
                    }
                }
                .labelsHidden()
            }

            slider("Border", value: $template.outerInset, in: 0...48, step: 1,
                   caption: "\(Int(template.outerInset))pt")
            slider("Gutter", value: $template.gutter, in: 0...32, step: 1,
                   caption: "\(Int(template.gutter))pt")
            slider("Footer", value: $template.footerHeight, in: 0...72, step: 1,
                   caption: "\(Int(template.footerHeight))pt")

            note("The border is also a per-strip setting. A strip that has "
                + "overridden its own border keeps that border.")
        }
        // Three columns of five photos is a half-empty row, so the choice is
        // never offered rather than refused after the fact.
        .onChange(of: template.frameCount) {
            if template.frameCount % template.columns != 0 { template.columns = 1 }
        }
    }

    private var footer: some View {
        HStack {
            if let failure {
                Text(failure)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    /// The same gate an import passes. Failure stays in the sheet: dismissing
    /// on a refusal would throw the edit away.
    private func save() {
        do {
            try TemplateImport.validate(template)
            let edited = template
            failure = nil
            dismiss()
            Task { await model.applyEdit(edit.replacing(edited)) }
        } catch {
            failure = error.localizedDescription
        }
    }

    private func slider(
        _ label: String, value: Binding<CGFloat>,
        in range: ClosedRange<Double>, step: Double, caption: String
    ) -> some View {
        slider(
            label,
            value: Binding(get: { Double(value.wrappedValue) },
                           set: { value.wrappedValue = CGFloat($0) }),
            in: range, step: step, caption: caption
        )
    }

    private func slider(
        _ label: String, value: Binding<Double>,
        in range: ClosedRange<Double>, step: Double, caption: String
    ) -> some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                // Tinted grey rather than accented: the chrome carries no hue,
                // and this one sits beside a preview of the paper (ADR-004).
                Slider(value: value, in: range, step: step)
                    .tint(.secondary)
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var shots: Binding<Double> {
        Binding(
            get: { Double(template.frameCount) },
            set: { template.frameCount = Int($0) }
        )
    }

    /// Only counts that divide the shot count, so the two controls together
    /// cannot describe a grid with a half-empty row.
    private var divisors: [Int] {
        (1...max(1, template.frameCount)).filter { template.frameCount % $0 == 0 }
    }

    private var paper: Binding<Paper> {
        Binding(
            get: { Paper(template.canvasSize) },
            set: { template.canvasSize = $0.size }
        )
    }

    /// Plus whatever this template already is: a hand-written file may hold a
    /// size no menu offers, and the picker must not silently snap it to one.
    private var papers: [Paper] {
        let presets = [
            Paper(CGSize(width: 144, height: 432)),
            Paper(CGSize(width: 288, height: 432)),
            Paper(CGSize(width: 288, height: 288)),
            Paper(CGSize(width: 432, height: 288)),
        ]
        let current = Paper(template.canvasSize)
        return presets.contains(current) ? presets : presets + [current]
    }
}

/// `CGSize` is only `Hashable` from macOS 15, and the deployment target is 14
/// (ADR-006), so the two sides are carried separately for the `Picker`.
private struct Paper: Hashable, Identifiable {
    var width: CGFloat
    var height: CGFloat

    init(_ size: CGSize) {
        width = size.width
        height = size.height
    }

    var id: Self { self }
    var size: CGSize { CGSize(width: width, height: height) }

    var inches: String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        let sides = [width, height].map {
            formatter.string(from: NSNumber(value: Double($0) / 72)) ?? "?"
        }
        return "\(sides[0]) x \(sides[1]) in"
    }
}

/// Not a render: drawn from the same `photoRects()` the renderer reads, so it
/// costs nothing on a drag and can't drift from the actual output.
private struct TemplateWireframe: View {
    let template: StripTemplate

    var body: some View {
        GeometryReader { proxy in
            let canvas = template.canvasSize
            let scale = fit(canvas, in: proxy.size)
            Canvas { context, _ in
                let paper = CGRect(
                    x: 0, y: 0,
                    width: canvas.width * scale, height: canvas.height * scale
                )
                context.fill(Path(paper), with: .color(Color(white: 0.12)))
                for rect in template.photoRects() {
                    context.fill(
                        Path(
                            roundedRect: flipped(rect, in: canvas, scale: scale),
                            cornerRadius: template.cornerRadius * scale
                        ),
                        with: .color(Color(white: 0.30))
                    )
                }
                let footer = template.footerRect()
                if footer.height > 0 {
                    context.fill(
                        Path(flipped(footer, in: canvas, scale: scale)),
                        with: .color(Color(white: 0.18))
                    )
                }
            }
            .frame(width: canvas.width * scale, height: canvas.height * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(
            "\(template.frameCount) photos in \(template.columns) column"
                + (template.columns == 1 ? "" : "s")
        )
    }

    private func fit(_ canvas: CGSize, in available: CGSize) -> CGFloat {
        guard canvas.width > 0, canvas.height > 0 else { return 0 }
        return min(available.width / canvas.width, available.height / canvas.height)
    }

    /// CoreGraphics counts up from the bottom, `Canvas` down from the top, so
    /// the renderer's rect has to be turned over to draw here.
    private func flipped(_ rect: CGRect, in canvas: CGSize, scale: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX * scale,
            y: (canvas.height - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}
