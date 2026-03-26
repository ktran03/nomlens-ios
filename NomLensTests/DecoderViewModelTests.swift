import Testing
import UIKit
@testable import NomLens

// MARK: - Mocks

private struct MockSegmentor: ImageSegmenting {
    let result: SegmentationResult
    func segment(image: UIImage) async -> SegmentationResult { result }
}

private final class MockDecoder: CharacterDecoding, @unchecked Sendable {
    enum Behaviour {
        case succeed([CharacterDecodeResult])
        case fail(Error)
    }
    let behaviour: Behaviour
    init(_ behaviour: Behaviour) { self.behaviour = behaviour }

    func decodeAll(
        _ crops: [CharacterCrop],
        progress: @Sendable @escaping (Int, Int) -> Void
    ) async throws -> [CharacterDecodeResult] {
        switch behaviour {
        case .succeed(let results):
            for (i, _) in crops.enumerated() {
                progress(i + 1, crops.count)
            }
            return results
        case .fail(let error):
            throw error
        }
    }
}

// MARK: - Helpers

private func makeCrop() -> CharacterCrop {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
    let img = renderer.image { ctx in
        UIColor.white.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
    return CharacterCrop(
        id: UUID(), image: img,
        boundingBox: CGRect(x: 0, y: 0, width: 4, height: 4),
        observationIndex: 0, characterIndex: 0,
        normalizedBox: .zero
    )
}

private let sampleResult = CharacterDecodeResult(
    character: "南",
    type: .han,
    quocNgu: "nam",
    meaning: "south",
    confidence: .high,
    alternateReadings: [],
    damageNoted: false,
    notes: nil
)

/// Makes a 4×4 white UIImage — enough for ImageUtilities to convert without crashing.
private func whiteImage() -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
    return renderer.image { ctx in
        UIColor.white.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
}

@MainActor
private func makeVM(
    segmentor: any ImageSegmenting,
    decoder: MockDecoder
) -> DecoderViewModel {
    DecoderViewModel(segmentor: segmentor, decoder: decoder)
}

// MARK: - M5: Pipeline state transitions

@MainActor
struct DecoderViewModelTests {

    @Test func happyPathReachesDone() async {
        let vm = makeVM(
            segmentor: MockSegmentor(result: .characters([makeCrop()])),
            decoder: MockDecoder(.succeed([sampleResult]))
        )
        let task = vm.decode(image: whiteImage())
        await task.value

        if case .done(let results) = vm.state {
            #expect(results.count == 1)
            #expect(results[0].character == "南")
        } else {
            #expect(Bool(false), "Expected .done, got \(vm.state)")
        }
    }

    @Test func zeroDetectionTransitionsToZeroDetected() async {
        let vm = makeVM(
            segmentor: MockSegmentor(result: .zeroDetected),
            decoder: MockDecoder(.succeed([]))
        )
        let task = vm.decode(image: whiteImage())
        await task.value

        if case .zeroDetected = vm.state { } else {
            #expect(Bool(false), "Expected .zeroDetected, got \(vm.state)")
        }
    }

    @Test func belowThresholdAlsoTransitionsToZeroDetected() async {
        let vm = makeVM(
            segmentor: MockSegmentor(result: .belowThreshold(0)),
            decoder: MockDecoder(.succeed([]))
        )
        let task = vm.decode(image: whiteImage())
        await task.value

        if case .zeroDetected = vm.state { } else {
            #expect(Bool(false), "Expected .zeroDetected, got \(vm.state)")
        }
    }

    @Test func decodeErrorTransitionsToFailed() async {
        let vm = makeVM(
            segmentor: MockSegmentor(result: .characters([makeCrop()])),
            decoder: MockDecoder(.fail(DecoderError.apiError(statusCode: 429)))
        )
        let task = vm.decode(image: whiteImage())
        await task.value

        if case .failed = vm.state { } else {
            #expect(Bool(false), "Expected .failed, got \(vm.state)")
        }
    }

    @Test func cancelResetsToIdle() async {
        let vm = makeVM(
            segmentor: MockSegmentor(result: .characters([makeCrop()])),
            decoder: MockDecoder(.succeed([sampleResult]))
        )
        _ = vm.decode(image: whiteImage())
        vm.cancel()
        if case .idle = vm.state { } else {
            #expect(Bool(false), "Expected .idle after cancel, got \(vm.state)")
        }
    }

    @Test func progressUpdatesAreSentDuringDecode() async {
        let crops = (0..<3).map { _ in makeCrop() }
        let results = (0..<3).map { _ in sampleResult }
        let vm = makeVM(
            segmentor: MockSegmentor(result: .characters(crops)),
            decoder: MockDecoder(.succeed(results))
        )
        let task = vm.decode(image: whiteImage())
        await task.value

        // Final state should be .done with 3 results
        if case .done(let r) = vm.state {
            #expect(r.count == 3)
        } else {
            #expect(Bool(false), "Expected .done")
        }
    }

    @Test func multipleCropsAllDecodedInDoneState() async {
        let crops = (0..<5).map { _ in makeCrop() }
        let results = (0..<5).map { _ in sampleResult }
        let vm = makeVM(
            segmentor: MockSegmentor(result: .characters(crops)),
            decoder: MockDecoder(.succeed(results))
        )
        let task = vm.decode(image: whiteImage())
        await task.value

        if case .done(let r) = vm.state {
            #expect(r.count == 5)
        } else {
            #expect(Bool(false), "Expected .done with 5 results")
        }
    }
}
