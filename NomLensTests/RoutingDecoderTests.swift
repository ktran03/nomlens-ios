import Testing
import UIKit
@testable import NomLens

// MARK: - Stubs

private struct StubClassifier: OnDeviceClassifying {
    let result: OnDeviceClassification?
    let shouldThrow: Bool

    init(character: String? = nil, confidence: Float = 0, shouldThrow: Bool = false) {
        self.result = character.map { OnDeviceClassification(character: $0, confidence: confidence) }
        self.shouldThrow = shouldThrow
    }

    func classify(crop: UIImage) async throws -> OnDeviceClassification? {
        if shouldThrow { throw URLError(.badServerResponse) }
        return result
    }
}

private struct StubFallback: CharacterDecoding, Sendable {
    let results: [CharacterDecodeResult]
    private(set) var callCount = 0

    func decodeAll(
        _ crops: [CharacterCrop],
        progress: @Sendable @escaping (Int, Int) -> Void
    ) async throws -> [CharacterDecodeResult] {
        results
    }
}

// MARK: - Helpers

private func makeCrop() -> CharacterCrop {
    let img = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        .image { $0.fill(CGRect(x: 0, y: 0, width: 4, height: 4)) }
    return CharacterCrop(
        id: .init(), image: img,
        boundingBox: CGRect(x: 0, y: 0, width: 4, height: 4),
        observationIndex: 0, characterIndex: 0,
        normalizedBox: CGRect(x: 0, y: 0, width: 1, height: 1)
    )
}

private let claudeResult = CharacterDecodeResult(
    character: "雨", type: .han, quocNgu: "vũ", meaning: "rain",
    confidence: .medium, alternateReadings: [], damageNoted: false, notes: nil
)

// MARK: - Tests

@Suite("RoutingDecoder")
struct RoutingDecoderTests {

    // MARK: High confidence → on-device, no Claude call

    @Test("confidence ≥ 90 % returns on-device result with .high")
    func highConfidenceAccepted() async throws {
        let decoder = RoutingDecoder(
            classifier: StubClassifier(character: "人", confidence: 0.95),
            fallback: StubFallback(results: [claudeResult])
        )
        let results = try await decoder.decodeAll([makeCrop()]) { _, _ in }
        #expect(results.count == 1)
        #expect(results[0].character == "人")
        #expect(results[0].confidence == .high)
    }

    // MARK: Medium confidence → on-device, .medium badge

    @Test("confidence 60–90 % returns on-device result with .medium")
    func mediumConfidenceAccepted() async throws {
        let decoder = RoutingDecoder(
            classifier: StubClassifier(character: "人", confidence: 0.75),
            fallback: StubFallback(results: [claudeResult])
        )
        let results = try await decoder.decodeAll([makeCrop()]) { _, _ in }
        #expect(results.count == 1)
        #expect(results[0].character == "人")
        #expect(results[0].confidence == .medium)
    }

    // MARK: Low confidence → escalate to Claude

    @Test("confidence < 60 % escalates to Claude")
    func lowConfidenceEscalates() async throws {
        let decoder = RoutingDecoder(
            classifier: StubClassifier(character: "人", confidence: 0.40),
            fallback: StubFallback(results: [claudeResult])
        )
        let results = try await decoder.decodeAll([makeCrop()]) { _, _ in }
        #expect(results[0].character == claudeResult.character)
        #expect(results[0].quocNgu == claudeResult.quocNgu)
    }

    // MARK: Classifier returns nil → escalate to Claude

    @Test("classifier returning nil escalates to Claude")
    func nilClassificationEscalates() async throws {
        let decoder = RoutingDecoder(
            classifier: StubClassifier(),   // result = nil
            fallback: StubFallback(results: [claudeResult])
        )
        let results = try await decoder.decodeAll([makeCrop()]) { _, _ in }
        #expect(results[0].character == claudeResult.character)
    }

    // MARK: Classifier throws → fail-safe escalate to Claude

    @Test("classifier error escalates to Claude rather than propagating")
    func classifierErrorEscalates() async throws {
        let decoder = RoutingDecoder(
            classifier: StubClassifier(shouldThrow: true),
            fallback: StubFallback(results: [claudeResult])
        )
        let results = try await decoder.decodeAll([makeCrop()]) { _, _ in }
        #expect(results[0].character == claudeResult.character)
    }

    // MARK: Progress callbacks

    @Test("progress fires once per crop")
    func progressCallbacks() async throws {
        let crops = [makeCrop(), makeCrop(), makeCrop()]
        let decoder = RoutingDecoder(
            classifier: StubClassifier(character: "人", confidence: 0.95),
            fallback: StubFallback(results: [])
        )
        var calls: [(Int, Int)] = []
        _ = try await decoder.decodeAll(crops) { done, total in
            calls.append((done, total))
        }
        #expect(calls.count == 3)
        #expect(calls.map(\.0) == [1, 2, 3])
        #expect(calls.allSatisfy { $0.1 == 3 })
    }

    // MARK: Mixed routing in one batch

    @Test("mixed confidence batch routes each crop independently")
    func mixedBatch() async throws {
        var callIndex = 0
        let confidences: [Float] = [0.95, 0.70, 0.30]
        let classifier = CallbackClassifier { _ in
            defer { callIndex += 1 }
            let c = confidences[callIndex]
            return OnDeviceClassification(character: "人", confidence: c)
        }
        let decoder = RoutingDecoder(
            classifier: classifier,
            fallback: StubFallback(results: [claudeResult])
        )
        let results = try await decoder.decodeAll([makeCrop(), makeCrop(), makeCrop()]) { _, _ in }
        #expect(results[0].confidence == .high)
        #expect(results[1].confidence == .medium)
        #expect(results[2].character  == claudeResult.character)  // escalated
    }
}

// MARK: - Callback classifier helper

private struct CallbackClassifier: OnDeviceClassifying {
    let block: @Sendable (UIImage) -> OnDeviceClassification?
    func classify(crop: UIImage) async throws -> OnDeviceClassification? { block(crop) }
}
