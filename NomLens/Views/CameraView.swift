import SwiftUI
import PhotosUI

/// Lets the user pick an image from the photo library or take a new photo.
struct CameraView: View {
    let onImagePicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var photosItem: PhotosPickerItem?
    @State private var showImagePicker = false
    @State private var loadError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "character.magnify")
                    .font(.system(size: 72))
                    .foregroundStyle(.secondary)

                VStack(spacing: 16) {
                    // Camera button (device only)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showImagePicker = true
                        } label: {
                            Label("Take Photo", systemImage: "camera.fill")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    // Photo library picker
                    PhotosPicker(
                        selection: $photosItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationTitle("New Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: photosItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        onImagePicked(image)
                        dismiss()
                    } else {
                        loadError = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showImagePicker) {
                ImagePickerController(onImagePicked: { image in
                    onImagePicked(image)
                    dismiss()
                })
                .ignoresSafeArea()
            }
            .alert("Could not load image", isPresented: $loadError) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

// MARK: - UIImagePickerController wrapper

private struct ImagePickerController: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePickerController
        init(_ parent: ImagePickerController) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
