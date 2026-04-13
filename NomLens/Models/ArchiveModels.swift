import Foundation

// MARK: - NLSource

struct NLSource: Codable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let title: String?
    let sourceType: SourceType
    let estimatedPeriod: String?
    let locationName: String
    let province: String?
    let country: String
    let condition: SourceCondition?
    let scanCount: Int
    let characterCount: Int
    let contributorDeviceId: String
    let isPublic: Bool
    let verified: Bool

    /// Populated only when fetched with `select=*,scans(...)`
    let scans: [NLScan]?

    enum CodingKeys: String, CodingKey {
        case id, title, condition, province, country, verified
        case createdAt           = "created_at"
        case updatedAt           = "updated_at"
        case sourceType          = "source_type"
        case estimatedPeriod     = "estimated_period"
        case locationName        = "location_name"
        case scanCount           = "scan_count"
        case characterCount      = "character_count"
        case contributorDeviceId = "contributor_device_id"
        case isPublic            = "is_public"
        case scans
    }

    // MARK: Source type

    enum SourceType: String, Codable, CaseIterable, Sendable {
        case stoneStele          = "stone_stele"
        case woodenInscription   = "wooden_inscription"
        case paperManuscript     = "paper_manuscript"
        case printedBook         = "printed_book"
        case templeSign          = "temple_sign"
        case rubbing             = "rubbing"
        case other               = "other"

        var label: String {
            switch self {
            case .stoneStele:        return "Stone Stele"
            case .woodenInscription: return "Wooden Inscription"
            case .paperManuscript:   return "Paper Manuscript"
            case .printedBook:       return "Printed Book"
            case .templeSign:        return "Temple Sign"
            case .rubbing:           return "Rubbing / Ink Print"
            case .other:             return "Other"
            }
        }

        var icon: String {
            switch self {
            case .stoneStele:        return "rectangle.portrait"
            case .woodenInscription: return "door.left.hand.open"
            case .paperManuscript:   return "scroll"
            case .printedBook:       return "book.closed"
            case .templeSign:        return "building.columns"
            case .rubbing:           return "square.and.pencil"
            case .other:             return "questionmark.square"
            }
        }
    }

    // MARK: Condition

    enum SourceCondition: String, Codable, CaseIterable, Sendable {
        case excellent
        case good
        case weathered
        case damaged
        case severelyDamaged = "severely_damaged"

        var label: String {
            switch self {
            case .excellent:      return "Excellent"
            case .good:           return "Good"
            case .weathered:      return "Weathered"
            case .damaged:        return "Damaged"
            case .severelyDamaged: return "Severely Damaged"
            }
        }
    }
}

// MARK: - NLSourceNear

struct NLSourceNear: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String?
    let locationName: String
    let sourceType: NLSource.SourceType
    let scanCount: Int
    let characterCount: Int
    let distanceM: Double

    enum CodingKeys: String, CodingKey {
        case id, title
        case locationName   = "location_name"
        case sourceType     = "source_type"
        case scanCount      = "scan_count"
        case characterCount = "character_count"
        case distanceM      = "distance_m"
    }
}

// MARK: - NLScan

struct NLScan: Codable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let sourceId: UUID
    let contributorDeviceId: String
    let imagePath: String?
    let thumbnailPath: String?
    let characterCount: Int
    let transliteration: String?
    let decodeResults: [DecodeResult]?
    let hasCorrections: Bool

    enum CodingKeys: String, CodingKey {
        case id, transliteration
        case createdAt           = "created_at"
        case sourceId            = "source_id"
        case contributorDeviceId = "contributor_device_id"
        case imagePath           = "image_path"
        case thumbnailPath       = "thumbnail_path"
        case characterCount      = "character_count"
        case decodeResults       = "decode_results"
        case hasCorrections      = "has_corrections"
    }

    struct DecodeResult: Codable, Sendable {
        let index: Int
        let unicode: String
        let quocNgu: String?
        let confidence: String?
        let scriptType: String?

        enum CodingKeys: String, CodingKey {
            case index, unicode, confidence
            case quocNgu    = "quoc_ngu"
            case scriptType = "script_type"
        }
    }
}

// MARK: - NLCharacter

struct NLCharacter: Codable, Identifiable, Sendable {
    let id: UUID?
    let scanId: UUID
    let sourceId: UUID
    let positionIndex: Int
    let unicodeChar: String
    let quocNgu: String?
    let meaning: String?
    let confidence: ConfidenceLevel?
    let scriptType: ScriptType?
    let isCorrected: Bool

    enum CodingKeys: String, CodingKey {
        case id, meaning, confidence
        case scanId        = "scan_id"
        case sourceId      = "source_id"
        case positionIndex = "position_index"
        case unicodeChar   = "unicode_char"
        case quocNgu       = "quoc_ngu"
        case scriptType    = "script_type"
        case isCorrected   = "is_corrected"
    }

    enum ConfidenceLevel: String, Codable, Sendable { case high, medium, low }
    enum ScriptType: String, Codable, Sendable { case han, nom }
}

// MARK: - Insert payloads

struct NewSource: Encodable, Sendable {
    let title: String?
    let sourceType: NLSource.SourceType
    let estimatedPeriod: String?
    let locationName: String
    let province: String?
    let country: String
    /// WKT: "SRID=4326;POINT(<lng> <lat>)"
    let coordinates: String?
    let condition: NLSource.SourceCondition?
    let contributorDeviceId: String

    enum CodingKeys: String, CodingKey {
        case title, province, country, coordinates, condition
        case sourceType          = "source_type"
        case estimatedPeriod     = "estimated_period"
        case locationName        = "location_name"
        case contributorDeviceId = "contributor_device_id"
    }
}

struct NewScan: Encodable, Sendable {
    let sourceId: UUID
    let contributorDeviceId: String
    let imagePath: String?
    let thumbnailPath: String?
    let characterCount: Int
    let transliteration: String?
    let decodeResults: [NLScan.DecodeResult]?
    let hasCorrections: Bool

    enum CodingKeys: String, CodingKey {
        case transliteration
        case sourceId            = "source_id"
        case contributorDeviceId = "contributor_device_id"
        case imagePath           = "image_path"
        case thumbnailPath       = "thumbnail_path"
        case characterCount      = "character_count"
        case decodeResults       = "decode_results"
        case hasCorrections      = "has_corrections"
    }
}

struct NewCharacter: Encodable, Sendable {
    let scanId: UUID
    let sourceId: UUID
    let positionIndex: Int
    let unicodeChar: String
    let quocNgu: String?
    let meaning: String?
    let confidence: NLCharacter.ConfidenceLevel?
    let scriptType: NLCharacter.ScriptType?
    let isCorrected: Bool

    enum CodingKeys: String, CodingKey {
        case meaning, confidence
        case scanId        = "scan_id"
        case sourceId      = "source_id"
        case positionIndex = "position_index"
        case unicodeChar   = "unicode_char"
        case quocNgu       = "quoc_ngu"
        case scriptType    = "script_type"
        case isCorrected   = "is_corrected"
    }

    // Explicit implementation so every object in a bulk-insert array has
    // identical keys. PostgREST (PGRST102) rejects arrays where some objects
    // omit keys that others include. Using `encode` (not `encodeIfPresent`)
    // writes `null` for nils instead of omitting the key entirely.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scanId,        forKey: .scanId)
        try c.encode(sourceId,      forKey: .sourceId)
        try c.encode(positionIndex, forKey: .positionIndex)
        try c.encode(unicodeChar,   forKey: .unicodeChar)
        try c.encode(quocNgu,       forKey: .quocNgu)
        try c.encode(meaning,       forKey: .meaning)
        try c.encode(confidence,    forKey: .confidence)
        try c.encode(scriptType,    forKey: .scriptType)
        try c.encode(isCorrected,   forKey: .isCorrected)
    }
}
