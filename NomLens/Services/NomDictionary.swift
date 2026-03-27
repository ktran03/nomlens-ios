import Foundation

/// Looks up Mandarin pinyin, Sino-Vietnamese quốc ngữ, and English definitions
/// from the bundled Unihan dataset (unihan_trimmed.json).
///
/// Usage:
/// ```swift
/// let entry = NomDictionary.shared.lookup("人")   // codepoint "4EBA"
/// entry?.mandarin   // "rén"
/// entry?.vietnamese // "nhân"
/// entry?.definition // "man; people; mankind; someone else"
/// ```
final class NomDictionary {

    static let shared = NomDictionary()

    struct Entry {
        let mandarin: String?
        let vietnamese: String?
        let definition: String?
    }

    private let table: [String: Entry]

    private init() {
        guard let url  = Bundle.main.url(forResource: "unihan_trimmed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw  = try? JSONDecoder().decode([String: RawEntry].self, from: data)
        else {
            table = [:]
            return
        }
        var built = [String: Entry](minimumCapacity: raw.count)
        for (key, r) in raw {
            built[key] = Entry(mandarin: r.m, vietnamese: r.v, definition: r.d)
        }
        table = built
    }

    /// Look up by Unicode character (e.g. "人"). Returns nil if not found.
    func lookup(_ character: String?) -> Entry? {
        guard let character,
              let scalar = character.unicodeScalars.first
        else { return nil }
        let hex = String(scalar.value, radix: 16, uppercase: true)
        return table[hex]
    }

    // MARK: - Private

    private struct RawEntry: Decodable {
        let m: String?  // mandarin
        let v: String?  // vietnamese
        let d: String?  // definition
    }
}
