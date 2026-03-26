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
    case decoding(progress: Int, total: Int)
    case done([CharacterDecodeResult])
    case zeroDetected
    case failed(Error)
}

// MARK: - ViewModel

/// Orchestrates the full decode pipeline:
/// preprocess → segment → decode → publish results.
///
/// All state mutations happen on the main actor.
/// Inject `segmentor` and `decoder` for unit testing.
@MainActor
final class DecoderViewModel: ObservableObject {

    @Published private(set) var state: DecoderState = .idle

    private let preprocessor: ImagePreprocessor
    private let segmentor: any ImageSegmenting
    private let decoder: any CharacterDecoding
    private let settings: PreprocessingSettings

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

    /// Start the pipeline. Returns the underlying Task so callers (e.g. tests)
    /// can await completion with `task.value`.
    @discardableResult
    func decode(image: UIImage) -> Task<Void, Never> {
        currentTask?.cancel()
        let task = Task { await run(image: image) }
        currentTask = task
        return task
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        state = .idle
    }

    // MARK: - Pipeline

    private func run(image: UIImage) async {
        // 1. Preprocess
        state = .preprocessing
        guard let ciIn = ImageUtilities.ciImage(from: image) else {
            state = .failed(DecoderError.imageEncodingFailed)
            return
        }
        let processed = preprocessor.process(image: ciIn, settings: settings)

        guard !Task.isCancelled else { return }

        // 2. Convert processed CIImage → UIImage for Vision
        guard let uiProcessed = ImageUtilities.uiImage(from: processed,
                                                        context: preprocessor.context) else {
            state = .failed(DecoderError.imageEncodingFailed)
            return
        }

        // 3. Segment
        state = .segmenting
        let segResult = await segmentor.segment(image: uiProcessed)

        guard !Task.isCancelled else { return }

        switch segResult {
        case .zeroDetected, .belowThreshold:
            state = .zeroDetected

        case .characters(let crops):
            // 4. Decode
            state = .decoding(progress: 0, total: crops.count)
            do {
                let results = try await decoder.decodeAll(crops) { done, total in
                    Task { @MainActor [weak self] in
                        // Guard prevents a queued progress update from overwriting
                        // .done after decodeAll has already returned.
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
}
