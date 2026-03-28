import UIKit
import Combine

// MARK: - Injectable protocols

/// Abstracts `CharacterSegmentor` for test injection.
protocol ImageSegmenting: Sendable {
    func segment(image: UIImage) async -> SegmentationResult
}

/// Abstracts `ClaudeService.decodeAll` for test injection.
protocol CharacterDecoding: Sendable {
    func decodeAll(
        _ crops: [CharacterCrop],
        progress: @Sendable @escaping (Int, Int) -> Void
    ) async throws -> [CharacterDecodeResult]
}

// MARK: - Conformances

extension CharacterSegmentor: ImageSegmenting {}
extension ClaudeService: CharacterDecoding {}

// MARK: - State

enum DecoderState {
    case idle
    case preprocessing
    case segmenting
    /// Segmentation complete — waiting for user to confirm before spending API calls.
    case segmented([CharacterCrop])
    /// Two strategies produced different counts — waiting for user to choose one.
    case segmentedOptions(optionA: [CharacterCrop], optionB: [CharacterCrop])
    case decoding(progress: Int, total: Int)
    case done([CharacterDecodeResult])
    case zeroDetected
    case failed(Error)
}

// MARK: - ViewModel

/// Orchestrates the decode pipeline in two user-visible phases:
///   1. `segmentOnly(image:)` → preprocess → segment → `.segmented`
///   2. `startDecoding()`     → decode all crops → `.done`
///
/// The combined `decode(image:)` runs both phases without pausing (used by tests).
///
/// All state mutations happen on the main actor.
/// Inject `segmentor` and `decoder` for unit testing.
@MainActor
final class DecoderViewModel: ObservableObject {

    @Published private(set) var state: DecoderState = .idle

    /// Retains the crops used in the most recent decode pass so that
    /// downstream views (e.g. ResultView) can show the original crop image
    /// alongside the decoded character.
    private(set) var lastCrops: [CharacterCrop] = []

    private let preprocessor: ImagePreprocessor
    private let segmentor: any ImageSegmenting
    let decoder: any CharacterDecoding
    var settings: PreprocessingSettings
    private let exporter = CropExporter()

    private var currentTask: Task<Void, Never>?

    init(
        preprocessor: ImagePreprocessor = ImagePreprocessor(),
        segmentor: any ImageSegmenting = CharacterSegmentor(),
        decoder: any CharacterDecoding,
        settings: PreprocessingSettings = .init()
    ) {
        self.preprocessor = preprocessor
        self.segmentor    = segmentor
        self.decoder      = decoder
        self.settings     = settings
    }

    // MARK: - Public API

    /// Phase 1: preprocess + segment only. Stops at `.segmented`.
    @discardableResult
    func segmentOnly(image: UIImage) -> Task<Void, Never> {
        currentTask?.cancel()
        let task = Task { await runSegment(image: image, thenDecode: false) }
        currentTask = task
        return task
    }

    /// Phase 2: decode the crops from the current `.segmented` state.
    @discardableResult
    func startDecoding() -> Task<Void, Never> {
        guard case .segmented(let crops) = state else {
            return Task {}
        }
        currentTask?.cancel()
        let task = Task { await runDecode(crops: crops) }
        currentTask = task
        return task
    }

    /// Decode an explicit crop list — used by CropEditorView after the user
    /// has manually added or removed crops.
    @discardableResult
    func startDecoding(crops: [CharacterCrop]) -> Task<Void, Never> {
        currentTask?.cancel()
        let task = Task { await runDecode(crops: crops) }
        currentTask = task
        return task
    }

    /// Full pipeline (preprocess → segment → decode). Used by tests and the
    /// "decode everything automatically" path.
    @discardableResult
    func decode(image: UIImage) -> Task<Void, Never> {
        currentTask?.cancel()
        let task = Task { await runSegment(image: image, thenDecode: true) }
        currentTask = task
        return task
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        state = .idle
    }

    // MARK: - Computed helpers

    var isWorking: Bool {
        switch state {
        case .preprocessing, .segmenting, .decoding: return true
        default: return false
        }
    }

    var segmentedCrops: [CharacterCrop]? {
        if case .segmented(let crops) = state { return crops }
        return nil
    }

    var segmentedOptions: ([CharacterCrop], [CharacterCrop])? {
        if case .segmentedOptions(let a, let b) = state { return (a, b) }
        return nil
    }

    var isSegmentedOptions: Bool {
        if case .segmentedOptions = state { return true }
        return false
    }

    /// Commit one of the two picker options and advance to the segmented state.
    func chooseSegmentation(_ crops: [CharacterCrop]) {
        state = .segmented(crops)
    }

    var currentResults: [CharacterDecodeResult]? {
        if case .done(let r) = state { return r }
        return nil
    }

    var progressFraction: Double {
        if case .decoding(let done, let total) = state, total > 0 {
            return Double(done) / Double(total)
        }
        return 0
    }

    var isDone: Bool {
        if case .done = state { return true }
        return false
    }

    var isZeroDetected: Bool {
        if case .zeroDetected = state { return true }
        return false
    }

    var isSegmented: Bool {
        if case .segmented = state { return true }
        return false
    }

    var failureMessage: String? {
        if case .failed(let error) = state { return error.localizedDescription }
        return nil
    }

    // MARK: - Pipeline internals

    private func runSegment(image: UIImage, thenDecode: Bool) async {
        state = .preprocessing
        // Yield so SwiftUI can render the state change before heavy work begins.
        await Task.yield()

        // Run Core Image preprocessing off the main thread.
        let prep = preprocessor
        let currentSettings = settings
        let preprocessed: UIImage? = await Task.detached(priority: .userInitiated) {
            guard let ciIn = ImageUtilities.ciImage(from: image) else { return nil }
            let processed = prep.process(image: ciIn, settings: currentSettings)
            return ImageUtilities.uiImage(from: processed, context: prep.context)
        }.value

        guard !Task.isCancelled else { return }
        guard let uiProcessed = preprocessed else {
            state = .failed(DecoderError.imageEncodingFailed)
            return
        }

        state = .segmenting
        await Task.yield()

        let seg = segmentor
        let segResult = await Task.detached(priority: .userInitiated) {
            await seg.segment(image: uiProcessed)
        }.value
        guard !Task.isCancelled else { return }

        switch segResult {
        case .zeroDetected:
            state = .zeroDetected
        case .belowThreshold:
            state = .zeroDetected
        case .twoOptions(let a, let b):
            // Re-crop display images from the original (un-preprocessed) camera image
            // so thumbnails show the natural colour rather than the binarized version.
            let optA = recropImages(a, from: image)
            let optB = recropImages(b, from: image)
            state = .segmentedOptions(optionA: optA, optionB: optB)
        case .characters(let crops):
            let display = recropImages(crops, from: image)
            if thenDecode {
                await runDecode(crops: display)
            } else {
                state = .segmented(display)
            }
        }
    }

    /// Replaces the `image` inside each crop with a fresh cut from `original`.
    /// Bounding boxes are in pixel space and match the original since preprocessing
    /// preserves image dimensions.
    private func recropImages(_ crops: [CharacterCrop], from original: UIImage) -> [CharacterCrop] {
        guard let cgImage = original.cgImage else { return crops }
        return crops.map { crop in
            guard let croppedCG = cgImage.cropping(to: crop.boundingBox) else { return crop }
            let cropUI = UIImage(cgImage: croppedCG,
                                 scale: original.scale,
                                 orientation: original.imageOrientation)
            return CharacterCrop(id: crop.id, image: cropUI,
                                 boundingBox: crop.boundingBox,
                                 observationIndex: crop.observationIndex,
                                 characterIndex: crop.characterIndex,
                                 normalizedBox: crop.normalizedBox)
        }
    }

    private func runDecode(crops: [CharacterCrop]) async {
        lastCrops = crops
        state = .decoding(progress: 0, total: crops.count)
        do {
            let results = try await decoder.decodeAll(crops) { done, total in
                Task { @MainActor [weak self] in
                    if case .decoding = self?.state {
                        self?.state = .decoding(progress: done, total: total)
                    }
                }
            }
            guard !Task.isCancelled else { return }
            exporter.export(crops: crops, results: results, inputSource: settings.inputSource)
            state = .done(results)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error)
        }
    }
}
