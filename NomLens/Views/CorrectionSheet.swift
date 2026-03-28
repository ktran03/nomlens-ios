import SwiftUI
import PencilKit

/// Detail sheet for a decoded character.
///
/// Shows the model's top predictions as a tappable grid.
/// The "Draw" tab lets the user sketch the character with their finger;
/// "Find matches" runs the sketch through the on-device model and
/// replaces the grid with the new top candidates.
struct CorrectionSheet: View {
    let cropImage: UIImage?
    let original: CharacterDecodeResult
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.classifyDrawing) private var classifyDrawing

    @State private var selected: String
    @State private var candidates: [String]
    @State private var mode: Mode = .predictions
    @State private var canvasView = PKCanvasView()
    @State private var isSearching = false
    @State private var customInput: String = ""

    private let dict = NomDictionary.shared

    enum Mode { case predictions, draw }

    init(cropImage: UIImage?, original: CharacterDecodeResult, onSave: @escaping (String) -> Void) {
        self.cropImage = cropImage
        self.original  = original
        self.onSave    = onSave
        let initial    = original.character ?? ""
        self._selected   = State(initialValue: initial)
        var all: [String] = []
        if let c = original.character { all.append(c) }
        all.append(contentsOf: original.alternateReadings)
        self._candidates = State(initialValue: all)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Mode picker ───────────────────────────────────────────────
                Picker("Mode", selection: $mode) {
                    Text("Predictions").tag(Mode.predictions)
                    Text("Draw").tag(Mode.draw)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // ── Content ───────────────────────────────────────────────────
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
                        if !selected.isEmpty, selected != orig {
                            onSave(selected)
                        }
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
                // Crop reference
                if let crop = cropImage {
                    Image(uiImage: crop)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 100)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if candidates.isEmpty {
                    Text("No predictions available.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 90), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(Array(candidates.enumerated()), id: \.offset) { _, char in
                            candidateButton(char: char)
                        }
                    }
                    .padding(.horizontal)
                }

                // Custom input
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
                .padding(.horizontal)
            }
            .padding(.vertical, 20)
        }
    }

    // MARK: - Draw tab

    private var drawContent: some View {
        VStack(spacing: 16) {
            // Crop reference
            if let crop = cropImage {
                Image(uiImage: crop)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 100)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 12)
            }

            Text("Draw the character with your finger")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Canvas
            DrawingCanvas(canvasView: $canvasView)
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4)))
                .padding(.horizontal)

            // Controls
            HStack(spacing: 12) {
                Button {
                    canvasView.drawing = PKDrawing()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    Task { await searchFromDrawing() }
                } label: {
                    Group {
                        if isSearching {
                            ProgressView().tint(.white)
                        } else {
                            Label("Find matches", systemImage: "magnifyingglass")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isSearching || canvasView.drawing.strokes.isEmpty || classifyDrawing == nil)
            }
            .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Drawing search

    private func searchFromDrawing() async {
        guard let classify = classifyDrawing else { return }
        isSearching = true
        defer { isSearching = false }

        // Render the canvas strokes to a UIImage on a white background.
        let bounds = CGRect(x: 0, y: 0, width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(bounds)
            let drawing = canvasView.drawing
            let scale = bounds.width / max(canvasView.bounds.width, 1)
            ctx.cgContext.scaleBy(x: scale, y: scale)
            drawing.image(from: canvasView.bounds, scale: 1).draw(in: canvasView.bounds)
        }

        let results = await classify(image)
        if !results.isEmpty {
            candidates = results
            selected   = results[0]
            mode       = .predictions   // switch back so user sees the new grid
        }
    }

    // MARK: - Candidate button

    @ViewBuilder
    private func candidateButton(char: String) -> some View {
        let isSelected = selected == char
        let entry = dict.lookup(char)

        Button {
            selected = char
            customInput = ""
        } label: {
            VStack(spacing: 4) {
                Text(char)
                    .font(.system(size: 40))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                if let vn = entry?.vietnamese {
                    Text(vn)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)
                }

                if let meaning = entry?.definition {
                    Text(meaning)
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
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
}

// MARK: - PencilKit canvas wrapper

private struct DrawingCanvas: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 12)
        canvasView.drawingPolicy = .anyInput   // finger + Apple Pencil
        canvasView.backgroundColor = .white
        canvasView.isOpaque = true
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
