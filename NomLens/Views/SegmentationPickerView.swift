import SwiftUI

/// Three-way segmentation chooser:
/// - Standard / Valley split → decode immediately with the chosen crops.
/// - Custom → open CropEditorView with an empty canvas.
struct SegmentationPickerView: View {
    let sourceImage: UIImage
    let optionA: [CharacterCrop]   // standard column-first
    let optionB: [CharacterCrop]   // row-first with valley splitting
    @ObservedObject var vm: DecoderViewModel
    let onCustom: () -> Void       // navigate to CropEditorView (empty)
    let onDone: () -> Void         // navigate to results after decode

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Pick a segmentation strategy, or draw your own crop boxes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                autoCard(label: "Standard", crops: optionA)
                autoCard(label: "Valley split", crops: optionB)
                customCard
            }
            .padding(.top)
            .padding(.bottom, 24)
        }
        .navigationTitle("Choose Segmentation")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: vm.isDone) { _, done in
            if done { onDone() }
        }
    }

    // MARK: - Auto option card

    @ViewBuilder
    private func autoCard(label: String, crops: [CharacterCrop]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                            boxOverlay(crop: crop, displaySize: geo.size)
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

            Button {
                vm.startDecoding(crops: crops)
            } label: {
                Text("Use this — \(crops.count) characters")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(vm.isWorking)
            .padding(.horizontal)
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Custom card

    private var customCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Custom")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            Text("Neither result looks right? Draw your own crop boxes directly on the image.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button {
                onCustom()
            } label: {
                Label("Draw crop boxes", systemImage: "rectangle.dashed")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                    )
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Box overlay

    @ViewBuilder
    private func boxOverlay(crop: CharacterCrop, displaySize: CGSize) -> some View {
        let sX = displaySize.width  / sourceImage.size.width
        let sY = displaySize.height / sourceImage.size.height
        let b  = crop.boundingBox
        Rectangle()
            .stroke(Color.accentColor, lineWidth: 1.5)
            .frame(width: b.width * sX, height: b.height * sY)
            .offset(x: b.minX * sX, y: b.minY * sY)
    }
}
