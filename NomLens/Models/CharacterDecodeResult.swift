import Foundation

/// The structured JSON payload returned by Claude for a single character.
/// Kept in its own file to avoid Swift 6 main-actor isolation bleed from
/// the `@Model`-annotated `DecodingSession` in `DecodingResult.swift`.
struct CharacterDecodeResult: Codable, Sendable {

    /// The Unicode Han/Nôm character, or nil if unrecognisable.
    let character: String?

    /// Whether this is a Han character, a native Nôm character, or unclear.
    let type: CharacterType?

    /// Quốc ngữ transliteration (modern Vietnamese romanisation).
    let quocNgu: String?

    /// Brief English meaning.
    let meaning: String?

    /// Claude's stated confidence level.
    let confidence: ConfidenceLevel

    /// Other plausible readings when the glyph is ambiguous.
    let alternateReadings: [String]

    /// True if Claude noted visible damage or degradation.
    let damageNoted: Bool

    /// Free-text notes on ambiguity, damage, or edge cases.
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case character
        case type
        case quocNgu            = "quoc_ngu"
        case meaning
        case confidence
        case alternateReadings  = "alternate_readings"
        case damageNoted        = "damage_noted"
        case notes
    }
}

// MARK: - Factory helpers

extension CharacterDecodeResult {
    /// Result produced by the on-device classifier with optional dictionary lookup.
    static func onDevice(
        character: String,
        confidence: ConfidenceLevel,
        quocNgu: String? = nil,
        mandarin: String? = nil,
        meaning: String? = nil,
        alternateReadings: [String] = []
    ) -> Self {
        let notes: String? = mandarin.map { "pinyin: \($0)" }
        return CharacterDecodeResult(
            character: character,
            type: nil,
            quocNgu: quocNgu,
            meaning: meaning,
            confidence: confidence,
            alternateReadings: alternateReadings,
            damageNoted: false,
            notes: notes
        )
    }

    /// Placeholder used when no result could be produced.
    static var unknown: Self {
        CharacterDecodeResult(
            character: nil,
            type: nil,
            quocNgu: nil,
            meaning: nil,
            confidence: .none,
            alternateReadings: [],
            damageNoted: false,
            notes: nil
        )
    }
}

// MARK: - Supporting enums

extension CharacterDecodeResult {
    enum CharacterType: String, Codable, Sendable {
        case han
        case nom
        case unclear
    }

    enum ConfidenceLevel: String, Codable, Sendable {
        case high
        case medium
        case low
        case none
    }
}
