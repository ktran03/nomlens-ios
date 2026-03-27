import Foundation
import UIKit

// MARK: - Schema (matches DATA_STRATEGY.md exactly)

private struct TrainingCrop: Codable {
    /// Base64-encoded JPEG of the raw crop at original resolution.
    let cropImage: String
    /// Unicode codepoint as uppercase hex string e.g. "4EBA" for 人.
    /// Nil if the character was unrecognised.
    let label: String?
    /// Who produced the label.
    let labelSource: String     // "claude" | "user_correction"
    /// How the source image was captured.
    let inputSource: String     // "digital" | "manuscript_photo"
    /// Numeric confidence 0.0–1.0, or nil when unavailable.
    /// Claude returns categorical confidence, not a float, so this is nil
    /// for all Claude-sourced crops. On-device model results will populate it.
    let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case cropImage   = "crop_image"
        case label
        case labelSource = "label_source"
        case inputSource = "input_source"
        case confidence
    }
}

private struct TrainingSession: Codable {
    let sessionId: String
    let timestamp: String       // ISO 8601
    let crops: [TrainingCrop]

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case timestamp
        case crops
    }
}

// MARK: - Exporter

/// Writes one JSON training file to `Documents/NomLens/training/` after every
/// successful decode. Called from `DecoderViewModel` — never blocks the UI.
///
/// Output filename: `{ISO-date}_{session-uuid}.json`
struct CropExporter {

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// - Parameters:
    ///   - crops:       Segmented character crops in decode order.
    ///   - results:     Claude decode results in the same order.
    ///   - inputSource: `"digital"` or `"manuscript_photo"` — derived from preprocessing preset.
    func export(
        crops: [CharacterCrop],
        results: [CharacterDecodeResult],
        inputSource: String
    ) {
        Task.detached(priority: .background) {
            do {
                try self.write(crops: crops, results: results, inputSource: inputSource)
            } catch {
                print("[NomLens] CropExporter error: \(error)")
            }
        }
    }

    // MARK: - Private

    private func write(
        crops: [CharacterCrop],
        results: [CharacterDecodeResult],
        inputSource: String
    ) throws {
        let dir = exportDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let sessionId = UUID().uuidString
        let timestamp = Self.iso8601.string(from: Date())

        var trainingCrops: [TrainingCrop] = []

        for (i, crop) in crops.enumerated() {
            guard let jpeg = ImageUtilities.base64JPEG(from: crop.image) else { continue }
            let result = i < results.count ? results[i] : nil

            trainingCrops.append(TrainingCrop(
                cropImage:   jpeg,
                label:       unicodeCodepoint(result?.character),
                labelSource: "claude",
                inputSource: inputSource,
                confidence:  nil   // Claude gives categorical confidence, not a float
            ))
        }

        let session = TrainingSession(
            sessionId: sessionId,
            timestamp: timestamp,
            crops:     trainingCrops
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)

        let safeTimestamp = timestamp.replacingOccurrences(of: ":", with: "-")
        let filename = "\(safeTimestamp)_\(sessionId).json"
        try data.write(
            to: dir.appendingPathComponent(filename),
            options: .atomic
        )
        print("[NomLens] CropExporter saved \(trainingCrops.count) crops → \(filename)")
    }

    /// Converts a rendered character to its Unicode codepoint hex string.
    /// "人" → "4EBA", "𡨸" → "21A38". Returns nil for nil input.
    private func unicodeCodepoint(_ character: String?) -> String? {
        guard let char = character,
              let scalar = char.unicodeScalars.first
        else { return nil }
        return String(format: "%04X", scalar.value)
    }

    private func exportDirectory() -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NomLens/training")
    }
}
