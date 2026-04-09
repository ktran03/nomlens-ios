import SwiftUI
import Combine
import SwiftData

// MARK: - Service container

/// Creates all services once at startup and surfaces any configuration error.
// MARK: - Environment key for draw-to-classify

/// Injected at the NavigationStack level so CorrectionSheet can run a
/// user's drawing through the on-device model from anywhere in the tree.
struct ClassifyDrawingKey: EnvironmentKey {
    static let defaultValue: (@Sendable (UIImage) async -> [String])? = nil
}

extension EnvironmentValues {
    var classifyDrawing: (@Sendable (UIImage) async -> [String])? {
        get { self[ClassifyDrawingKey.self] }
        set { self[ClassifyDrawingKey.self] = newValue }
    }
}

// MARK: - Service container

/// Creates all services once at startup and surfaces any configuration error.
@MainActor
private final class ServiceContainer: ObservableObject {
    let viewModel: DecoderViewModel?
    let classifierProxy: ClassifierProxy
    let setupError: String?
    @Published var isModelReady = false

    init() {
        let proxy = ClassifierProxy()
        self.classifierProxy = proxy

        // In DEBUG builds, bypass Claude and use the on-device model only.
        // In release, the RoutingDecoder uses Claude as a low-confidence fallback.
        #if DEBUG
        let onDeviceOnly = true
        #else
        let onDeviceOnly = false
        #endif

        let decoder: any CharacterDecoding
        if onDeviceOnly {
            decoder = OnDeviceDecoder(proxy)
        } else if let claude = try? ClaudeService() {
            decoder = RoutingDecoder(classifier: proxy, fallback: claude)
        } else {
            // System prompt missing — fall back to on-device only.
            decoder = OnDeviceDecoder(proxy)
        }
        viewModel  = DecoderViewModel(decoder: decoder)
        setupError = nil

        // All stored properties are set — safe to capture self.
        let manager = ModelManager(proxy: proxy) { [weak self] in
            self?.isModelReady = true
        }

        Task { await manager.loadStoredModel() }
        Task { await manager.loadBundledModelIfNeeded() }
        Task { await manager.checkForUpdates() }

        // DEBUG only: load a local model file if present, bypassing bundle + OTA.
        // Set NOMlens_LOCAL_MODEL_PATH in your environment or update the path below.
        // This block is stripped from release builds — release uses the bundled model.
        #if DEBUG
        Task {
            let localModelPath = ProcessInfo.processInfo.environment["NOMlens_LOCAL_MODEL_PATH"]
                ?? "/Users/kt/Documents/NomLensMLModel/export/NomLensClassifier_3.0.0.mlpackage"
            let localURL = URL(fileURLWithPath: localModelPath)
            if FileManager.default.fileExists(atPath: localURL.path) {
                await manager.loadModel(at: localURL)
            }
        }
        #endif
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
            let hits = (try? await classifier.classifyTopN(crop: crop.image, n: 5)) ?? []
            if let top = hits.first {
                let level: CharacterDecodeResult.ConfidenceLevel =
                    top.confidence >= 0.90 ? .high :
                    top.confidence >= 0.60 ? .medium : .low
                let entry = dict.lookup(top.character)
                let alternates = hits.dropFirst().map { $0.character }
                results.append(.onDevice(
                    character:        top.character,
                    confidence:       level,
                    quocNgu:          entry?.vietnamese,
                    mandarin:         entry?.mandarin,
                    meaning:          entry?.definition,
                    alternateReadings: alternates
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
    case segmentationPicker(WrappedImage)   // two options read from vm.segmentedOptions
    case cropEditor(WrappedImage)           // crops read from vm.segmentedCrops
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
        .environment(\.classifyDrawing) { [proxy = container.classifierProxy] image in
            let hits = (try? await proxy.classifyTopN(crop: image, n: 30)) ?? []
            return hits.map(\.character)
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
            HomeView {
                vm.cancel()
                showCamera = true
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
                        navPath.append(Route.cropEditor(wrapped))
                    },
                    onOptions: {
                        navPath.append(Route.segmentationPicker(wrapped))
                    },
                    onZeroDetected: {
                        navPath.removeLast()
                        showCamera = true
                    }
                )
            }

        case .segmentationPicker(let wrapped):
            if let vm = container.viewModel, let (optA, optB) = vm.segmentedOptions {
                SegmentationPickerView(
                    sourceImage: wrapped.image,
                    optionA: optA,
                    optionB: optB,
                    vm: vm,
                    onCustom: {
                        vm.chooseSegmentation([])
                        navPath.append(Route.cropEditor(wrapped))
                    },
                    onDone: {
                        navPath.append(Route.results(wrapped))
                    }
                )
            }

        case .cropEditor(let wrapped):
            if let vm = container.viewModel {
                CropEditorView(
                    sourceImage: wrapped.image,
                    initialCrops: vm.segmentedCrops ?? [],
                    vm: vm,
                    isModelReady: container.isModelReady,
                    onDone: {
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
