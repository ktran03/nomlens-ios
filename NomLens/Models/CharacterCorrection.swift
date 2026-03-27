import Foundation
import SwiftData

/// A user-submitted correction for a single decoded character.
///
/// Corrections are the highest-quality training signal — verified ground truth
/// labels attached to real crop images from real manuscripts.
/// The training pipeline exports these for Phase 2+ fine-tuning.
@Model
final class CharacterCorrection {
    var id: UUID
    var createdAt: Date

    /// JPEG of the segmented character crop that was decoded.
    var cropImageData: Data?

    /// What the decoder returned (nil if it returned unknown).
    var originalCharacter: String?

    /// What the user says the character actually is.
    var correctedCharacter: String

    /// Raw confidence level at the time of decode ("high", "medium", "low", "none").
    var originalConfidence: String

    init(
        cropImageData: Data?,
        originalCharacter: String?,
        correctedCharacter: String,
        originalConfidence: String
    ) {
        self.id                  = UUID()
        self.createdAt           = Date()
        self.cropImageData       = cropImageData
        self.originalCharacter   = originalCharacter
        self.correctedCharacter  = correctedCharacter
        self.originalConfidence  = originalConfidence
    }
}
