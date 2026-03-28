import CoreML
import Vision
import UIKit

// MARK: - Result type

/// Output from a single on-device classification pass.
struct OnDeviceClassification: Sendable {
    let character: String
    /// Softmax confidence in [0, 1]. Note: neural-network softmax is systematically
    /// overconfident; calibrate thresholds with temperature scaling after training.
    let confidence: Float
}

// MARK: - Protocol

/// Abstracts the on-device classifier so `RoutingDecoder` and tests can inject fakes.
protocol OnDeviceClassifying: Sendable {
    func classify(crop: UIImage) async throws -> OnDeviceClassification?
}

// MARK: - Real implementation

/// Wraps a Core ML image-classification model.
///
/// Load after `ModelManager` has downloaded the `.mlpackage` file:
/// ```swift
/// let classifier = try NomClassifier(modelURL: downloadedURL)
/// ```
/// The model must accept a single image input and produce `VNClassificationObservation`
/// results (i.e. be a Core ML classifier, not a custom neural network with raw outputs).
final class NomClassifier: OnDeviceClassifying, @unchecked Sendable {

    private let visionModel: VNCoreMLModel

    /// Load from a `.mlpackage` (uncompiled) or `.mlmodelc` (pre-compiled).
    /// Pass `compiledURL` when `ModelManager` has already compiled and cached
    /// the model — avoids recompiling on every launch.
    init(modelURL: URL) throws {
        let compiledURL: URL
        if modelURL.pathExtension == "mlmodelc" {
            compiledURL = modelURL
        } else {
            // MLModel.compileModel writes to a system temp directory.
            // ModelManager moves the result to a stable cache path after init.
            compiledURL = try MLModel.compileModel(at: modelURL)
        }
        let mlModel = try MLModel(contentsOf: compiledURL)
        self.visionModel = try VNCoreMLModel(for: mlModel)
    }

    /// Converts a hex codepoint string (e.g. `"4EBA"`) to its Unicode character (`"人"`).
    /// Falls back to the identifier as-is if it isn't a valid codepoint.
    private static func characterFromCodepoint(_ identifier: String) -> String {
        guard let value = UInt32(identifier, radix: 16),
              let scalar = Unicode.Scalar(value)
        else { return identifier }
        return String(scalar)
    }

    func classify(crop: UIImage) async throws -> OnDeviceClassification? {
        return try await classifyTopN(crop: crop, n: 1).first
    }

    /// Returns up to `n` predictions sorted by descending confidence.
    func classifyTopN(crop: UIImage, n: Int) async throws -> [OnDeviceClassification] {
        guard let cgImage = crop.cgImage else { return [] }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: visionModel) { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (req.results as? [VNClassificationObservation]) ?? []
                let top = observations.prefix(n).map {
                    OnDeviceClassification(
                        character: Self.characterFromCodepoint($0.identifier),
                        confidence: $0.confidence
                    )
                }
                continuation.resume(returning: top)
            }
            request.imageCropAndScaleOption = .centerCrop

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
