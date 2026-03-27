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

    init(modelURL: URL) throws {
        let mlModel = try MLModel(contentsOf: modelURL)
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
        guard let cgImage = crop.cgImage else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: visionModel) { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let results = req.results as? [VNClassificationObservation],
                      let top = results.first
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: OnDeviceClassification(
                    character: Self.characterFromCodepoint(top.identifier),
                    confidence: top.confidence
                ))
            }
            // Center-crop scales the image to the model's expected input size.
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
