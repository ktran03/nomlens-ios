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

        // Merge chunom.org supplemental dictionary — fills definition gaps for
        // Nôm-specific characters that Unihan doesn't cover.
        if let supURL  = Bundle.main.url(forResource: "nom_supplemental", withExtension: "json"),
           let supData = try? Data(contentsOf: supURL),
           let supRaw  = try? JSONDecoder().decode([String: SupEntry].self, from: supData) {
            for (key, s) in supRaw {
                if let existing = built[key] {
                    // Only fill in fields that are missing in the Unihan entry.
                    let mergedVietnamese  = existing.vietnamese  ?? s.v
                    let mergedDefinition  = existing.definition  ?? s.d
                    if mergedVietnamese != existing.vietnamese || mergedDefinition != existing.definition {
                        built[key] = Entry(mandarin: existing.mandarin,
                                           vietnamese: mergedVietnamese,
                                           definition: mergedDefinition)
                    }
                } else {
                    built[key] = Entry(mandarin: nil, vietnamese: s.v, definition: s.d)
                }
            }
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

    private struct SupEntry: Decodable {
        let v: String?  // vietnamese
        let d: String?  // definition
    }
}
