import SwiftUI

/// Shows the source image with detected character bounding boxes overlaid.
/// The user reviews the segmentation before committing to API decode calls.
struct SegmentationReviewView: View {
    let sourceImage: UIImage
    let crops: [CharacterCrop]
    @ObservedObject var vm: DecoderViewModel
    let isModelReady: Bool

    let onDone: ([CharacterDecodeResult]) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Image with box overlays.
                // Using .overlay so the GeometryReader always matches the
                // actual displayed image frame — no UIScreen dependency.
                Image(uiImage: sourceImage)
                    .resizable()
                    .scaledToFit()
                    .overlay(alignment: .topLeading) {
                        GeometryReader { geo in
                            ForEach(crops) { crop in
                                boxOverlay(crop: crop,
                                           imageNaturalSize: sourceImage.size,
                                           displaySize: geo.size)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)

                // Summary
                HStack {
                    Image(systemName: "character.magnify")
                        .foregroundStyle(Color.accentColor)
                    Text("\(crops.count) character\(crops.count == 1 ? "" : "s") detected")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)

                // Decode progress or button
                if case .decoding(let done, let total) = vm.state {
                    VStack(spacing: 8) {
                        ProgressView(value: Double(done), total: Double(max(total, 1)))
                            .padding(.horizontal)
                        Text("Decoding \(done) / \(total)…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        vm.startDecoding()
                    } label: {
                        if isModelReady {
                            Text("Decode All (\(crops.count))")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            Label("Model Loading…", systemImage: "arrow.clockwise")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.secondary.opacity(0.3))
                                .foregroundStyle(.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .disabled(vm.isWorking || !isModelReady)
                    .padding(.horizontal)
                }
            }
            .padding(.top)
        }
        .navigationTitle("Review Segmentation")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: vm.isDone) { _, done in
            if done, let results = vm.currentResults {
                onDone(results)
            }
        }
    }

    // MARK: - Box overlay

    @ViewBuilder
    private func boxOverlay(crop: CharacterCrop,
                             imageNaturalSize: CGSize,
                             displaySize: CGSize) -> some View {
        let scaleX = displaySize.width  / imageNaturalSize.width
        let scaleY = displaySize.height / imageNaturalSize.height
        let b = crop.boundingBox

        Rectangle()
            .stroke(Color.accentColor, lineWidth: 1.5)
            .frame(width: b.width * scaleX, height: b.height * scaleY)
            .offset(x: b.minX * scaleX, y: b.minY * scaleY)
    }
}
