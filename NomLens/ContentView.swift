import SwiftUI
import Combine
import SwiftData

// MARK: - Service container

/// Creates all services once at startup and surfaces any configuration error.
@MainActor
private final class ServiceContainer: ObservableObject {
    let viewModel: DecoderViewModel?
    let setupError: String?

    init() {
        let proxy   = ClassifierProxy()
        let manager = ModelManager(proxy: proxy)

        // Set to true to skip Claude and use on-device model only.
        // Useful for testing the Core ML model without burning API calls.
        let onDeviceOnly = true

        let decoder: any CharacterDecoding
        if onDeviceOnly {
            decoder = RoutingDecoder(classifier: proxy, fallback: NullDecoder())
        } else {
            guard let claude = try? ClaudeService() else {
                viewModel  = nil
                setupError = "CLAUDE_API_KEY not configured.\nAdd it to Config.xcconfig and re-run."
                return
            }
            decoder = RoutingDecoder(classifier: proxy, fallback: claude)
        }

        viewModel  = DecoderViewModel(decoder: decoder)
        setupError = nil

        Task { await manager.loadStoredModel() }
        Task { await manager.checkForUpdates() }

        // Temporary: load the epoch-17 model directly for on-device testing.
        // Remove once ModelManager OTA delivery is wired to a real endpoint.
        Task {
            let e17 = URL(fileURLWithPath: "/Users/kt/Documents/NomLensMLModel/export/NomLensClassifier_1.0.0-e17.mlpackage")
            if FileManager.default.fileExists(atPath: e17.path) {
                await manager.loadModel(at: e17)
            }
        }
    }
}

// MARK: - NullDecoder

/// No-op fallback used when Claude is disabled (e.g. on-device testing).
/// Returns `.unknown` for every crop so the app still renders results.
private struct NullDecoder: CharacterDecoding, Sendable {
    func decodeAll(
        _ crops: [CharacterCrop],
        progress: @Sendable @escaping (Int, Int) -> Void
    ) async throws -> [CharacterDecodeResult] {
        for (i, _) in crops.enumerated() { progress(i + 1, crops.count) }
        return crops.map { _ in .unknown }
    }
}

// MARK: - Navigation routes

private enum Route: Hashable {
    case preprocessing(WrappedImage)
    case segmentationReview(WrappedImage)   // crops read from vm.segmentedCrops
    case results(WrappedImage)              // results read from vm.currentResults
}

/// `UIImage` is not `Hashable`. Wrap it with a stable UUID for NavigationStack.
private struct WrappedImage: Hashable {
    let id = UUID()
    let image: UIImage
    static func == (lhs: WrappedImage, rhs: WrappedImage) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Root view

struct ContentView: View {
    @StateObject private var container = ServiceContainer()
    @State private var showCamera = false
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            root
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .sheet(isPresented: $showCamera) {
            CameraView { image in
                navPath.append(Route.preprocessing(WrappedImage(image: image)))
            }
        }
    }

    // MARK: - Root screen

    @ViewBuilder
    private var root: some View {
        if let vm = container.viewModel {
            ZStack(alignment: .bottom) {
                HistoryView()

                Button {
                    vm.cancel()
                    showCamera = true
                } label: {
                    Label("New Scan", systemImage: "camera.fill")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(radius: 6, y: 3)
                }
                .padding(.bottom, 24)
            }
        } else {
            setupErrorView
        }
    }

    // MARK: - Navigation destinations

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .preprocessing(let wrapped):
            if let vm = container.viewModel {
                PreprocessingView(
                    sourceImage: wrapped.image,
                    vm: vm,
                    onSegmented: { _ in
                        navPath.append(Route.segmentationReview(wrapped))
                    },
                    onZeroDetected: {
                        navPath.removeLast()
                        showCamera = true
                    }
                )
            }

        case .segmentationReview(let wrapped):
            if let vm = container.viewModel {
                SegmentationReviewView(
                    sourceImage: wrapped.image,
                    crops: vm.segmentedCrops ?? [],
                    vm: vm,
                    onDone: { _ in
                        navPath.append(Route.results(wrapped))
                    }
                )
            }

        case .results(let wrapped):
            if let vm = container.viewModel, let results = vm.currentResults {
                ResultView(
                    sourceImage: wrapped.image,
                    results: results,
                    cropImages: vm.lastCrops.map(\.image)
                )
            }
        }
    }

    // MARK: - Error screen

    private var setupErrorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.slash")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Configuration Required")
                .font(.title2.bold())
            Text(container.setupError ?? "Unknown error")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("NomLens")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: DecodingSession.self, inMemory: true)
}
