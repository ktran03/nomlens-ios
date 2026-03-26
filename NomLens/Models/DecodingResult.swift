import Foundation
import SwiftData

/// A completed decode session stored in SwiftData history.
@Model
final class DecodingSession {
    var id: UUID
    var createdAt: Date

    /// The original photo as JPEG data.
    var sourceImageData: Data?

    /// Assembled Quốc ngữ transliteration for the full page.
    var fullTransliteration: String

    /// Assembled English meaning summary.
    var fullMeaning: String

    /// Number of characters successfully decoded.
    var characterCount: Int

    /// Serialised array of `CharacterDecodeResult` values (JSON).
    var characterResultsJSON: Data?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceImageData: Data? = nil,
        fullTransliteration: String = "",
        fullMeaning: String = "",
        characterCount: Int = 0,
        characterResultsJSON: Data? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceImageData = sourceImageData
        self.fullTransliteration = fullTransliteration
        self.fullMeaning = fullMeaning
        self.characterCount = characterCount
        self.characterResultsJSON = characterResultsJSON
    }
}
