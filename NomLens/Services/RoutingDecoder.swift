import UIKit

// MARK: - Thresholds

/// Confidence thresholds that control on-device vs. cloud routing.
///
/// These are starting values — calibrate with temperature scaling after training
/// to ensure they correspond to real accuracy rates (raw softmax is overconfident).
enum RoutingThreshold {
    /// On-device result accepted with high confidence.
    static let accept: Float = 0.90
    /// On-device result accepted but flagged for user review.
    static let review: Float = 0.60
    // Below `review` → escalate to Claude.
}

// MARK: - RoutingDecoder

/// Routes each character crop through the on-device classifier first,
/// escalating to Claude only when the on-device confidence is insufficient.
///
/// Routing rules:
/// ```
/// confidence ≥ 90 %  →  on-device result, .high confidence
/// confidence 60–90 % →  on-device result, .medium confidence (needs review)
/// confidence < 60 %  →  escalate to Claude
/// classifier throws  →  escalate to Claude (fail-safe)
/// ```
///
/// Conforms to `CharacterDecoding` so it drops in as a direct replacement
/// for `ClaudeService` in `DecoderViewModel` with no other changes.
actor RoutingDecoder: CharacterDecoding {

    private let classifier: any OnDeviceClassifying
    private let fallback:   any CharacterDecoding

    init(classifier: any OnDeviceClassifying, fallback: any CharacterDecoding) {
        self.classifier = classifier
        self.fallback   = fallback
    }

    // MARK: - CharacterDecoding

    func decodeAll(
        _ crops: [CharacterCrop],
        progress: @Sendable @escaping (Int, Int) -> Void
    ) async throws -> [CharacterDecodeResult] {
        var results: [CharacterDecodeResult] = []
        let total = crops.count

        for (index, crop) in crops.enumerated() {
            let result = try await route(crop: crop)
            results.append(result)
            progress(index + 1, total)
        }
        return results
    }

    // MARK: - Routing

    private func route(crop: CharacterCrop) async throws -> CharacterDecodeResult {
        // Classifier errors are non-fatal — treat them as low confidence and
        // fall through to Claude rather than surfacing an error to the user.
        var bestOnDevice: CharacterDecodeResult? = nil
        if let hit = try? await classifier.classify(crop: crop.image) {
            if hit.confidence >= RoutingThreshold.accept {
                return .onDevice(character: hit.character, confidence: .high)
            } else if hit.confidence >= RoutingThreshold.review {
                return .onDevice(character: hit.character, confidence: .medium)
            }
            // Below threshold — save result in case Claude is unavailable.
            bestOnDevice = .onDevice(character: hit.character, confidence: .low)
        }

        // Escalate to Claude. Pass a no-op progress callback — progress is
        // already tracked at the RoutingDecoder level per crop.
        do {
            let claudeResults = try await fallback.decodeAll([crop]) { _, _ in }
            return claudeResults.first ?? bestOnDevice ?? .unknown
        } catch DecoderError.missingAPIKey {
            // No key configured — return best on-device result rather than failing.
            return bestOnDevice ?? .unknown
        }
    }
}
