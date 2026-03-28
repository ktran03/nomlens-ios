import SwiftUI
import PencilKit

/// Detail sheet for a decoded character.
///
/// **Predictions tab** — top model candidates as a tappable grid.
/// **Draw tab** — sketch the character; live candidates update as you draw.
/// Tap any candidate to accept it and return immediately.
struct CorrectionSheet: View {
    let cropImage: UIImage?
    let original: CharacterDecodeResult
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.classifyDrawing) private var classifyDrawing

    @State private var selected: String
    @State private var candidates: [String]
    @State private var mode: Mode = .predictions

    // Draw tab state
    @State private var drawing = PKDrawing()
    @State private var liveCandidates: [String] = []
    @State private var classifyTask: Task<Void, Never>?

    // Predictions tab
    @State private var customInput: String = ""

    private let dict = NomDictionary.shared

    enum Mode { case predictions, draw }

    init(cropImage: UIImage?, original: CharacterDecodeResult, onSave: @escaping (String) -> Void) {
        self.cropImage = cropImage
        self.original  = original
        self.onSave    = onSave
        let initial = original.character ?? ""
        self._selected = State(initialValue: initial)
        var all: [String] = []
        if let c = original.character { all.append(c) }
        all.append(contentsOf: original.alternateReadings)
        self._candidates = State(initialValue: all)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    Text("Predictions").tag(Mode.predictions)
                    Text("Draw").tag(Mode.draw)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                if mode == .predictions {
                    predictionsContent
                } else {
                    drawContent
                }
            }
            .navigationTitle("Choose Character")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        let orig = original.character ?? ""
                        if !selected.isEmpty, selected != orig { onSave(selected) }
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Predictions tab

    private var predictionsContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                cropThumbnail

                if !candidates.isEmpty {
                    candidateGrid(candidates)
                        .padding(.horizontal)
                }

                customInputField
                    .padding(.horizontal)
            }
            .padding(.vertical, 20)
        }
    }

    // MARK: - Draw tab

    private var drawContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    cropThumbnail
                        .padding(.top, 12)

                    // Canvas
                    DrawingCanvas(drawing: $drawing)
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4)))
                        .padding(.horizontal)
                        .onChange(of: drawing) { _, newDrawing in
                            scheduleClassify(newDrawing)
                        }

                    Button {
                        drawing = PKDrawing()
                        liveCandidates = []
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .disabled(drawing.strokes.isEmpty)
                }
            }

            // Live results at the bottom
            if !liveCandidates.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tap to select")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(liveCandidates.enumerated()), id: \.offset) { _, char in
                                liveResultButton(char)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                }
                .background(Color(.systemBackground))
            }
        }
    }

    // MARK: - Shared subviews

    @ViewBuilder
    private var cropThumbnail: some View {
        if let crop = cropImage {
            Image(uiImage: crop)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 100)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func candidateGrid(_ chars: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
            ForEach(Array(chars.enumerated()), id: \.offset) { _, char in
                candidateButton(char: char)
            }
        }
    }

    private var customInputField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter a different character")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack {
                TextField("Han Nôm character", text: $customInput)
                    .font(.system(size: 36))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onChange(of: customInput) { _, val in
                        if !val.isEmpty { selected = val }
                    }

                Button("Use") {
                    let t = customInput.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    selected = t
                }
                .font(.body.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(customInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private func candidateButton(char: String) -> some View {
        let isSelected = selected == char
        let entry = dict.lookup(char)
        Button {
            selected = char
            customInput = ""
        } label: {
            VStack(spacing: 4) {
                Text(char).font(.system(size: 40)).minimumScaleFactor(0.5).lineLimit(1)
                if let vn = entry?.vietnamese {
                    Text(vn).font(.caption2.weight(.medium))
                        .foregroundStyle(isSelected ? .white : .primary).lineLimit(1)
                }
                if let meaning = entry?.definition {
                    Text(meaning).font(.system(size: 9))
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                        .lineLimit(2).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .padding(8)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    @ViewBuilder
    private func liveResultButton(_ char: String) -> some View {
        let entry = dict.lookup(char)
        Button {
            onSave(char)
            dismiss()
        } label: {
            VStack(spacing: 3) {
                Text(char).font(.system(size: 36)).lineLimit(1)
                if let vn = entry?.vietnamese {
                    Text(vn).font(.caption2.weight(.medium)).lineLimit(1)
                }
                if let meaning = entry?.definition {
                    Text(meaning).font(.system(size: 9)).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live classification

    private func scheduleClassify(_ newDrawing: PKDrawing) {
        classifyTask?.cancel()
        guard !newDrawing.strokes.isEmpty else { liveCandidates = []; return }
        classifyTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000) // 350 ms debounce
            guard !Task.isCancelled else { return }
            guard let classify = classifyDrawing else { return }
            let image = renderDrawing(newDrawing)
            let results = await classify(image)
            guard !Task.isCancelled else { return }
            liveCandidates = results
        }
    }

    private func renderDrawing(_ drawing: PKDrawing) -> UIImage {
        // Crop to the stroke bounds + 15% padding, composite on white.
        var bounds = drawing.bounds.insetBy(
            dx: -drawing.bounds.width  * 0.15,
            dy: -drawing.bounds.height * 0.15
        )
        if bounds.width < 10 || bounds.height < 10 {
            bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        }
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let scale = min(size.width / bounds.width, size.height / bounds.height)
            let tx = (size.width  - bounds.width  * scale) / 2 - bounds.minX * scale
            let ty = (size.height - bounds.height * scale) / 2 - bounds.minY * scale
            ctx.cgContext.translateBy(x: tx, y: ty)
            ctx.cgContext.scaleBy(x: scale, y: scale)
            drawing.image(from: bounds, scale: 1).draw(in: bounds)
        }
    }
}

// MARK: - PencilKit canvas wrapper

private struct DrawingCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.tool = PKInkingTool(.pen, color: .black, width: 12)
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.drawing = $drawing
        // Only sync canvas → state, not the other way, to avoid loops.
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        init(drawing: Binding<PKDrawing>) { self.drawing = drawing }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }
}
