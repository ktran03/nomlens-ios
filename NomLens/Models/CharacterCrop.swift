import UIKit

/// A single detected character region extracted from a segmented image.
/// Created by `CharacterSegmentor` and passed through the decode pipeline.
struct CharacterCrop: Identifiable {
    let id: UUID

    /// The cropped character image, padded slightly beyond the bounding box.
    let image: UIImage

    /// Pixel-space bounding box in the source CGImage (origin top-left).
    let boundingBox: CGRect

    /// Index of the `VNRecognizedTextObservation` this crop came from.
    let observationIndex: Int

    /// Index of this character within its observation's `characterBoxes`.
    let characterIndex: Int

    /// Normalized bounding box as returned by Vision (origin bottom-left, 0–1).
    let normalizedBox: CGRect

    // MARK: - Decode results (set after ClaudeService responds)

    /// The Unicode Han/Nôm character identified by Claude.
    var decodedCharacter: String?

    /// Quốc ngữ (modern Vietnamese romanization) for this character.
    var transliteration: String?

    /// Claude's confidence in the reading.
    var confidence: Confidence?

    /// True when Claude returned multiple plausible readings.
    var isAmbiguous: Bool = false

    /// Full decode payload returned by Claude.
    var decodeResult: CharacterDecodeResult?
}

// MARK: - Confidence

extension CharacterCrop {
    enum Confidence: String, Codable {
        case high
        case medium
        case low
        case none
    }
}
