import SwiftUI
import PhotosUI
import AVFoundation

/// Source picker shown when the user taps "New Scan".
/// Camera is the primary action; photo library is secondary.
struct CameraView: View {
    let onImagePicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var photosItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var cameraPermission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var loadError = false

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Dark branded background
                NomTheme.stone950.ignoresSafeArea()

                // Decorative character
                Text("攝")
                    .font(.system(size: 220, weight: .black, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.03))
                    .offset(x: 60, y: 60)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer()

                    // Icon
                    ZStack {
                        Circle()
                            .fill(NomTheme.lacquer500.opacity(0.15))
                            .frame(width: 100, height: 100)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(NomTheme.lacquer400)
                    }
                    .padding(.bottom, 24)

                    Text("New Scan")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .padding(.bottom, 8)

                    Text("Photograph or import a Han Nôm inscription")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Spacer()

                    // Action buttons
                    VStack(spacing: 12) {
                        // Primary: Camera
                        cameraButton

                        // Secondary: Photo library
                        PhotosPicker(
                            selection: $photosItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("Choose from Library", systemImage: "photo.on.rectangle")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white.opacity(0.08))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 48)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.85))
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
            .fullScreenCover(isPresented: $showCamera) {
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

    // MARK: - Camera button

    @ViewBuilder
    private var cameraButton: some View {
        if !cameraAvailable {
            // Simulator or device without camera — show disabled state
            VStack(spacing: 6) {
                Label("Take Photo", systemImage: "camera.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(NomTheme.lacquer500.opacity(0.3))
                    .foregroundStyle(.white.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text("Camera unavailable on this device")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
            }
        } else if cameraPermission == .denied || cameraPermission == .restricted {
            // Permission denied — prompt to open Settings
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                VStack(spacing: 4) {
                    Label("Take Photo", systemImage: "camera.fill")
                        .font(.title3.weight(.semibold))
                    Text("Tap to enable camera in Settings")
                        .font(.caption)
                        .opacity(0.75)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(NomTheme.lacquer500.opacity(0.5))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        } else {
            // Camera available — primary action
            Button {
                if cameraPermission == .authorized {
                    showCamera = true
                } else {
                    // .notDetermined — request permission first
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        DispatchQueue.main.async {
                            cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
                            if granted { showCamera = true }
                        }
                    }
                }
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(NomTheme.lacquer500)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: NomTheme.lacquer500.opacity(0.45), radius: 12, y: 4)
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
        picker.cameraCaptureMode = .photo
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
