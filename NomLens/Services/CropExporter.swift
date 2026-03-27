import Foundation
import UIKit

// MARK: - Schema

/// One crop + its Claude decode result, serialised for training.
struct TrainingCrop: Codable {
    let index: Int
    /// JPEG bytes, base64-encoded.
    let imageB64: String
    let boundingBox: BBox
    /// Raw Claude output for this crop (nil if unrecognised).
    let character: String?
    let quocNgu: String?
    let meaning: String?
    let confidence: String
    let type: String?

    struct BBox: Codable {
        let x, y, w, h: Double
    }

    enum CodingKeys: String, CodingKey {
        case index
        case imageB64       = "image_b64"
        case boundingBox    = "bounding_box"
        case character, quocNgu = "quoc_ngu", meaning, confidence, type
    }
}

/// One full decode session written to disk.
struct TrainingSession: Codable {
    let sessionId: String
    let createdAt: String           // ISO 8601
    let appVersion: String
    let crops: [TrainingCrop]

    enum CodingKeys: String, CodingKey {
        case sessionId   = "session_id"
        case createdAt   = "created_at"
        case appVersion  = "app_version"
        case crops
    }
}

// MARK: - Exporter

/// Writes a training record to `Documents/NomLens/training/` after every
/// successful decode. Runs entirely off the main thread.
///
/// Files are named `{ISO-date}_{session-uuid}.json` for easy sorting and
/// de-duplication. The training pipeline reads these directly.
///
/// Export is best-effort — failures are logged but never propagate to the UI.
struct CropExporter {

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Export `crops` + `results` as a single JSON training record.
    /// Safe to call from any thread / actor.
    func export(crops: [CharacterCrop], results: [CharacterDecodeResult]) {
        Task.detached(priority: .background) {
            do {
                try self.write(crops: crops, results: results)
            } catch {
                print("[NomLens] CropExporter failed: \(error)")
            }
        }
    }

    // MARK: - Private

    private func write(crops: [CharacterCrop], results: [CharacterDecodeResult]) throws {
        let dir = exportDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let sessionId = UUID().uuidString
        let now       = Date()
        let dateStr   = Self.iso8601.string(from: now)
        let version   = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        var trainingCrops: [TrainingCrop] = []

        for (i, crop) in crops.enumerated() {
            guard let jpeg = ImageUtilities.base64JPEG(from: crop.image) else { continue }
            let result = i < results.count ? results[i] : nil
            let b = crop.boundingBox

            trainingCrops.append(TrainingCrop(
                index:       i,
                imageB64:    jpeg,
                boundingBox: .init(x: b.minX, y: b.minY, w: b.width, h: b.height),
                character:   result?.character,
                quocNgu:     result?.quocNgu,
                meaning:     result?.meaning,
                confidence:  result?.confidence.rawValue ?? "none",
                type:        result?.type?.rawValue
            ))
        }

        let session = TrainingSession(
            sessionId:  sessionId,
            createdAt:  dateStr,
            appVersion: version,
            crops:      trainingCrops
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)

        // e.g. 2026-03-26T14-22-05Z_3F2A….json
        let safeDateStr = dateStr.replacingOccurrences(of: ":", with: "-")
        let filename    = "\(safeDateStr)_\(sessionId).json"
        let fileURL     = dir.appendingPathComponent(filename)

        try data.write(to: fileURL, options: .atomic)
        print("[NomLens] CropExporter saved \(trainingCrops.count) crops → \(filename)")
    }

    private func exportDirectory() -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NomLens/training")
    }
}
