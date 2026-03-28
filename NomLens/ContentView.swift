import SwiftUI
import Combine
import SwiftData

// MARK: - Service container

/// Creates all services once at startup and surfaces any configuration error.
@MainActor
private final class ServiceContainer: ObservableObject {
    let viewModel: DecoderViewModel?
    let setupError: String?
    @Published var isModelReady = false

    init() {
        let proxy = ClassifierProxy()

        // Set to true to skip Claude and use on-device model only.
        // Useful for testing the Core ML model without burning API calls.
        let onDeviceOnly = true

        let decoder: any CharacterDecoding
        if onDeviceOnly {
            decoder = OnDeviceDecoder(proxy)
            viewModel  = DecoderViewModel(decoder: decoder)
            setupError = nil
        } else {
            guard let claude = try? ClaudeService() else {
                viewModel  = nil
                setupError = "CLAUDE_API_KEY not configured.\nAdd it to Config.xcconfig and re-run."
                return
            }
            decoder    = RoutingDecoder(classifier: proxy, fallback: claude)
            viewModel  = DecoderViewModel(decoder: decoder)
            setupError = nil
        }

        // All stored properties are set — safe to capture self.
        let manager = ModelManager(proxy: proxy) { [weak self] in
            self?.isModelReady = true
        }

        Task { await manager.loadStoredModel() }
        Task { await manager.checkForUpdates() }

        // Temporary: load the epoch-17 model directly for on-device testing.
        // Remove once ModelManager OTA delivery is wired to a real endpoint.
        Task {
            let e17 = URL(fileURLWithPath: "/Users/kt/Documents/NomLensMLModel/export/NomLensClassifier_1.0.0.mlpackage")
            if FileManager.default.fileExists(atPath: e17.path) {
                await manager.loadModel(at: e17)
            }
        }
    }
}

// MARK: - NullDecoder

/// On-device-only decoder for testing — always returns whatever the model
/// produces, no confidence threshold cutoff. Confidence maps to badge colour:
/// ≥90% → high (green), 60–90% → medium (yellow), <60% → low (red).
private actor OnDeviceDecoder: CharacterDecoding {
    private let classifier: ClassifierProxy

    init(_ classifier: ClassifierProxy) { self.classifier = classifier }

    func decodeAll(
        _ crops: [CharacterCrop],
        progress: @Sendable @escaping (Int, Int) -> Void
    ) async throws -> [CharacterDecodeResult] {
        let dict = NomDictionary.shared
        var results: [CharacterDecodeResult] = []
        for (i, crop) in crops.enumerated() {
            if let hit = try? await classifier.classify(crop: crop.image) {
                let level: CharacterDecodeResult.ConfidenceLevel =
                    hit.confidence >= 0.90 ? .high :
                    hit.confidence >= 0.60 ? .medium : .low
                let entry = dict.lookup(hit.character)
                results.append(.onDevice(
                    character:   hit.character,
                    confidence:  level,
                    quocNgu:     entry?.vietnamese,
                    mandarin:    entry?.mandarin,
                    meaning:     entry?.definition
                ))
            } else {
                results.append(.unknown)
            }
            progress(i + 1, crops.count)
        }
        return results
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
        .overlay { workingOverlay }
        .sheet(isPresented: $showCamera) {
            CameraView { image in
                navPath.append(Route.preprocessing(WrappedImage(image: image)))
            }
        }
    }

    @ViewBuilder
    private var workingOverlay: some View {
        if let vm = container.viewModel {
            WorkingOverlay(vm: vm)
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
                    isModelReady: container.isModelReady,
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

// MARK: - Working overlay

/// Separate view so it can use @ObservedObject to subscribe to vm.state changes.
/// ContentView itself only observes ServiceContainer, so inline access to
/// vm.isWorking would never trigger a re-render when state changes.
private struct WorkingOverlay: View {
    @ObservedObject var vm: DecoderViewModel

    var body: some View {
        if vm.isWorking {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().scaleEffect(1.6).tint(.white)
                    Text(label).font(.headline).foregroundStyle(.white)
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        }
    }

    private var label: String {
        switch vm.state {
        case .preprocessing:             return "Preprocessing…"
        case .segmenting:                return "Segmenting…"
        case .decoding(let done, let total): return "Decoding \(done) / \(total)…"
        default:                         return "Working…"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: DecodingSession.self, inMemory: true)
}
