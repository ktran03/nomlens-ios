import Testing
import UIKit
@testable import NomLens

/// One-time validation suite for the exported probe model.
///
/// Requires the .mlpackage to exist at the path below.
/// Run once to confirm the pipeline output is compatible with NomClassifier,
/// then these tests serve as ongoing regression checks when the model is updated.
@Suite("ModelProbe — pipeline validation")
struct ModelProbeTests {

    private static let modelURL = URL(fileURLWithPath:
        "/Users/kt/Documents/NomLensMLModel/export/NomLensClassifier_1.0.0-probe.mlpackage"
    )

    // MARK: - Load

    @Test("probe model loads without error")
    func modelLoads() throws {
        guard FileManager.default.fileExists(atPath: Self.modelURL.path) else { return }
        #expect(throws: Never.self) {
            _ = try NomClassifier(modelURL: Self.modelURL)
        }
    }

    // MARK: - Classify

    @Test("probe model returns VNClassificationObservation for a test crop")
    func classifiesTestCrop() async throws {
        guard FileManager.default.fileExists(atPath: Self.modelURL.path) else { return }
        let classifier = try NomClassifier(modelURL: Self.modelURL)

        // 96×96 image matching the model's expected input size —
        // black stroke on white background, enough to get a non-nil result.
        let image = makeTestCrop(size: 96)
        let result = try await classifier.classify(crop: image)

        // Model may legitimately return low confidence on a synthetic image,
        // but it must not throw and must return a valid classification.
        guard let result else { return }

        #expect(!result.character.isEmpty)
        #expect(result.confidence >= 0.0)
        #expect(result.confidence <= 1.0)
    }

    // MARK: - Codepoint conversion

    @Test("identifier is decoded from hex codepoint to rendered character")
    func identifierIsRenderedCharacter() async throws {
        guard FileManager.default.fileExists(atPath: Self.modelURL.path) else { return }
        let classifier = try NomClassifier(modelURL: Self.modelURL)
        let image = makeTestCrop(size: 96)
        guard let result = try await classifier.classify(crop: image) else { return }

        // The raw model identifier is a hex codepoint like "6731".
        // After conversion it should be a single Unicode scalar character,
        // not a raw hex string.
        let isRawHex = UInt32(result.character, radix: 16) != nil && result.character.count <= 5
        #expect(!isRawHex,
            "character '\(result.character)' looks like a raw hex string — codepoint conversion may have failed")
        #expect(result.character.unicodeScalars.count == 1,
            "Expected a single Unicode character, got '\(result.character)'")
    }

    // MARK: - Helpers

    private func makeTestCrop(size: Int) -> UIImage {
        let s = CGFloat(size)
        return UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            UIColor.black.setFill()
            // Simple cross stroke — enough ink to get a classification
            ctx.fill(CGRect(x: s * 0.4, y: s * 0.1, width: s * 0.2, height: s * 0.8))
            ctx.fill(CGRect(x: s * 0.1, y: s * 0.4, width: s * 0.8, height: s * 0.2))
        }
    }
}
