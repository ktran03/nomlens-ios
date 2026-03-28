import SwiftUI

/// Shown when the two projection strategies produce different crop counts.
/// Displays both options with thumbnails so the user can pick the better one.
struct SegmentationPickerView: View {
    let sourceImage: UIImage
    let optionA: [CharacterCrop]   // standard column-first
    let optionB: [CharacterCrop]   // row-first with valley splitting
    @ObservedObject var vm: DecoderViewModel
    let onPicked: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Two segmentation strategies found different results. Pick the one that looks more accurate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                optionCard(label: "Standard", crops: optionA)
                optionCard(label: "Valley split", crops: optionB)
            }
            .padding(.top)
            .padding(.bottom, 24)
        }
        .navigationTitle("Choose Segmentation")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func optionCard(label: String, crops: [CharacterCrop]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .font(.headline)
                Text("· \(crops.count) character\(crops.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            // Source image with bounding boxes
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

            // Crop thumbnails
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(crops) { crop in
                        Image(uiImage: crop.image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal)
            }

            // Pick button
            Button {
                vm.chooseSegmentation(crops)
                onPicked()
            } label: {
                Text("Use this — \(crops.count) characters")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

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
