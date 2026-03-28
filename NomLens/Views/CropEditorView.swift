import SwiftUI

/// Interactive crop editor shown after segmentation.
///
/// - Tap an existing box to delete it.
/// - Drag on empty space to draw a new box.
/// - Tap "Decode All" when satisfied.
struct CropEditorView: View {
    let sourceImage: UIImage
    let initialCrops: [CharacterCrop]
    @ObservedObject var vm: DecoderViewModel
    let isModelReady: Bool
    let onDone: () -> Void

    @State private var crops: [CharacterCrop]
    @State private var displaySize: CGSize = .zero
    @State private var dragStart: CGPoint?
    @State private var currentDragRect: CGRect?

    init(
        sourceImage: UIImage,
        initialCrops: [CharacterCrop],
        vm: DecoderViewModel,
        isModelReady: Bool,
        onDone: @escaping () -> Void
    ) {
        self.sourceImage   = sourceImage
        self.initialCrops  = initialCrops
        self.vm            = vm
        self.isModelReady  = isModelReady
        self.onDone        = onDone
        self._crops        = State(initialValue: initialCrops)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Hint bar ──────────────────────────────────────────────────────
            Text("Tap a box to remove · Drag to add")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)

            // ── Scrollable image + overlays ───────────────────────────────────
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: sourceImage)
                    .resizable()
                    .scaledToFit()
                    .overlay(alignment: .topLeading) {
                        GeometryReader { geo in
                            // Capture display size for coordinate mapping.
                            Color.clear
                                .onAppear { displaySize = geo.size }
                                .onChange(of: geo.size) { _, s in displaySize = s }

                            // Existing crop boxes.
                            ForEach(crops) { crop in
                                boxView(for: crop, in: geo.size)
                            }

                            // Live drag preview.
                            if let rect = currentDragRect {
                                Rectangle()
                                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [6]))
                                    .frame(width: rect.width, height: rect.height)
                                    .offset(x: rect.minX, y: rect.minY)
                                    .allowsHitTesting(false)
                            }

                            // Transparent draw-gesture layer.
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(drawGesture(in: geo.size))
                        }
                    }
            }

            Divider()

            // ── Bottom decode button ──────────────────────────────────────────
            Group {
                if case .decoding(let done, let total) = vm.state {
                    VStack(spacing: 6) {
                        ProgressView(value: Double(done), total: Double(max(total, 1)))
                            .padding(.horizontal)
                        Text("Decoding \(done) / \(total)…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    Button {
                        vm.startDecoding(crops: crops)
                    } label: {
                        Label(
                            isModelReady
                                ? "Decode All (\(crops.count))"
                                : "Model Loading…",
                            systemImage: isModelReady ? "sparkles" : "arrow.clockwise"
                        )
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isModelReady ? Color.accentColor : Color.secondary.opacity(0.3))
                        .foregroundStyle(isModelReady ? .white : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(vm.isWorking || !isModelReady || crops.isEmpty)
                    .padding()
                }
            }
        }
        .navigationTitle("Edit Crops (\(crops.count))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Reset") { crops = initialCrops }
                    .disabled(crops.map(\.id) == initialCrops.map(\.id))
            }
        }
        .onChange(of: vm.isDone) { _, done in
            if done { onDone() }
        }
    }

    // MARK: - Box overlay

    @ViewBuilder
    private func boxView(for crop: CharacterCrop, in size: CGSize) -> some View {
        let b = crop.boundingBox
        let sX = size.width  / sourceImage.size.width
        let sY = size.height / sourceImage.size.height

        Rectangle()
            .stroke(Color.accentColor, lineWidth: 1.5)
            .frame(width: b.width * sX, height: b.height * sY)
            .offset(x: b.minX * sX, y: b.minY * sY)
            .contentShape(Rectangle()
                .offset(x: b.minX * sX, y: b.minY * sY))
            .onTapGesture {
                crops.removeAll { $0.id == crop.id }
            }
    }

    // MARK: - Draw gesture

    private func drawGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let start = dragStart ?? value.startLocation
                dragStart = start
                let end = value.location
                currentDragRect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
            }
            .onEnded { value in
                defer { dragStart = nil; currentDragRect = nil }
                let start = dragStart ?? value.startLocation
                let end = value.location
                let displayRect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                // Require a minimum size to avoid accidental taps.
                guard displayRect.width > 20, displayRect.height > 20 else { return }
                if let crop = makeCrop(from: displayRect, displaySize: size) {
                    crops.append(crop)
                }
            }
    }

    // MARK: - Crop creation

    private func makeCrop(from displayRect: CGRect, displaySize: CGSize) -> CharacterCrop? {
        guard displaySize.width > 0, displaySize.height > 0 else { return nil }
        let sX = sourceImage.size.width  / displaySize.width
        let sY = sourceImage.size.height / displaySize.height
        let pixelRect = CGRect(
            x: displayRect.minX * sX,
            y: displayRect.minY * sY,
            width: displayRect.width  * sX,
            height: displayRect.height * sY
        )
        guard let cgImage = sourceImage.cgImage,
              let croppedCG = cgImage.cropping(to: pixelRect) else { return nil }
        let cropUI = UIImage(cgImage: croppedCG,
                             scale: sourceImage.scale,
                             orientation: sourceImage.imageOrientation)
        let norm = CGRect(
            x: pixelRect.minX / sourceImage.size.width,
            y: 1 - pixelRect.maxY / sourceImage.size.height,
            width:  pixelRect.width  / sourceImage.size.width,
            height: pixelRect.height / sourceImage.size.height
        )
        return CharacterCrop(id: UUID(), image: cropUI,
                             boundingBox: pixelRect,
                             observationIndex: 0, characterIndex: 0,
                             normalizedBox: norm)
    }
}
