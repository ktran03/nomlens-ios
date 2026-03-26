import SwiftUI

/// Shows the source image with detected character bounding boxes overlaid.
/// The user reviews the segmentation before committing to API decode calls.
struct SegmentationReviewView: View {
    let sourceImage: UIImage
    let crops: [CharacterCrop]
    @ObservedObject var vm: DecoderViewModel

    let onDone: ([CharacterDecodeResult]) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Image with box overlays
                GeometryReader { geo in
                    let size = fittedSize(for: sourceImage.size, in: geo.size)
                    let offsetX = (geo.size.width - size.width) / 2

                    ZStack(alignment: .topLeading) {
                        Image(uiImage: sourceImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        ForEach(crops) { crop in
                            boxOverlay(crop: crop, imageSize: sourceImage.size,
                                       displaySize: size, offsetX: offsetX)
                        }
                    }
                    .frame(width: geo.size.width, height: size.height)
                }
                .frame(height: fittedHeight(for: sourceImage.size,
                                             containerWidth: UIScreen.main.bounds.width - 32))
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
                    Button(action: { vm.startDecoding() }) {
                        Text("Decode All (\(crops.count))")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(vm.isWorking)
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
                             imageSize: CGSize,
                             displaySize: CGSize,
                             offsetX: CGFloat) -> some View {
        let scaleX = displaySize.width  / imageSize.width
        let scaleY = displaySize.height / imageSize.height
        let b = crop.boundingBox

        Rectangle()
            .stroke(Color.accentColor, lineWidth: 1.5)
            .frame(width: b.width * scaleX, height: b.height * scaleY)
            .offset(x: offsetX + b.minX * scaleX,
                    y: b.minY * scaleY)
    }

    // MARK: - Geometry helpers

    private func fittedSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        let scale = min(container.width / imageSize.width,
                        container.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func fittedHeight(for imageSize: CGSize, containerWidth: CGFloat) -> CGFloat {
        guard imageSize.width > 0 else { return 300 }
        return containerWidth * imageSize.height / imageSize.width
    }
}
