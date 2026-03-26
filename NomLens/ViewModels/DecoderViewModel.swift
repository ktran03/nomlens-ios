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

    private let preprocessor: ImagePreprocessor
    private let segmentor: any ImageSegmenting
    let decoder: any CharacterDecoding
    var settings: PreprocessingSettings

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

    // MARK: - Pipeline internals

    private func runSegment(image: UIImage, thenDecode: Bool) async {
        state = .preprocessing
        guard let ciIn = ImageUtilities.ciImage(from: image) else {
            state = .failed(DecoderError.imageEncodingFailed)
            return
        }
        let processed = preprocessor.process(image: ciIn, settings: settings)
        guard !Task.isCancelled else { return }

        guard let uiProcessed = ImageUtilities.uiImage(from: processed,
                                                        context: preprocessor.context) else {
            state = .failed(DecoderError.imageEncodingFailed)
            return
        }

        state = .segmenting
        let segResult = await segmentor.segment(image: uiProcessed)
        guard !Task.isCancelled else { return }

        switch segResult {
        case .zeroDetected, .belowThreshold:
            state = .zeroDetected
        case .characters(let crops):
            if thenDecode {
                await runDecode(crops: crops)
            } else {
                state = .segmented(crops)
            }
        }
    }

    private func runDecode(crops: [CharacterCrop]) async {
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
            state = .done(results)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error)
        }
    }
}
