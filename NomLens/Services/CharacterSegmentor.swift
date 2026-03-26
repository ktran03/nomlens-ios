import UIKit
import Vision

/// Detects individual character regions in a preprocessed image using the
/// Vision framework, then sorts them into Han Nôm reading order.
///
/// Han Nôm reading order: columns run **right-to-left**;
/// within each column characters read **top-to-bottom**.
struct CharacterSegmentor {

    /// Minimum number of detected characters before `belowThreshold` is returned.
    static let minimumCharacterCount = 1

    // MARK: - Public API

    /// Segment characters from a preprocessed `UIImage`.
    /// - Returns: A `SegmentationResult` with crops already in reading order.
    func segment(image: UIImage) async -> SegmentationResult {
        guard let cgImage = image.cgImage else { return .zeroDetected }

        let observations = await runVision(on: cgImage)

        if observations.isEmpty {
            return .zeroDetected
        }

        let crops = buildCrops(from: observations, sourceImage: image, cgImage: cgImage)

        if crops.count < Self.minimumCharacterCount {
            return .belowThreshold(crops.count)
        }

        let sorted = sortIntoReadingOrder(crops)
        return .characters(sorted)
    }

    // MARK: - Vision

    private func runVision(on cgImage: CGImage) async -> [VNRecognizedTextObservation] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let obs = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: obs)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Crop extraction

    private func buildCrops(
        from observations: [VNRecognizedTextObservation],
        sourceImage: UIImage,
        cgImage: CGImage
    ) -> [CharacterCrop] {
        let imageW = CGFloat(cgImage.width)
        let imageH = CGFloat(cgImage.height)

        var crops: [CharacterCrop] = []

        for (obsIdx, obs) in observations.enumerated() {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string

            for (charIdx, char) in text.enumerated() {
                let charIndex = text.index(text.startIndex, offsetBy: charIdx)
                let range = charIndex ..< text.index(after: charIndex)
                guard let rect = try? candidate.boundingBox(for: range) else { continue }

                // Vision normalized box: origin bottom-left.
                // Convert to pixel-space with origin top-left.
                let norm = rect.boundingBox
                let pixelBox = CGRect(
                    x:      norm.minX * imageW,
                    y:      (1 - norm.maxY) * imageH,
                    width:  norm.width  * imageW,
                    height: norm.height * imageH
                )

                let clamped = clampedBox(pixelBox, imageWidth: imageW, imageHeight: imageH)
                guard clamped.width > 0, clamped.height > 0 else { continue }

                guard let croppedCG = cgImage.cropping(to: clamped) else { continue }
                let cropUI = UIImage(cgImage: croppedCG, scale: sourceImage.scale,
                                    orientation: sourceImage.imageOrientation)

                crops.append(CharacterCrop(
                    id: UUID(),
                    image: cropUI,
                    boundingBox: clamped,
                    observationIndex: obsIdx,
                    characterIndex: charIdx,
                    normalizedBox: norm
                ))
            }
        }

        return crops
    }

    // MARK: - Reading order sort (testable)

    /// Sorts crops into Han Nôm reading order:
    /// columns right-to-left, top-to-bottom within each column.
    ///
    /// Column assignment uses a dynamic width equal to the median character width,
    /// clamped to [8%, 20%] of the image width to handle extreme outliers.
    func sortIntoReadingOrder(_ crops: [CharacterCrop]) -> [CharacterCrop] {
        guard crops.count > 1 else { return crops }

        // Derive column width from median character width.
        let colWidth = dynamicColumnWidth(crops)

        // Assign each crop to a column bucket using its horizontal centre.
        // Buckets are keyed by the left edge of the column band the centre falls in.
        func columnBucket(_ crop: CharacterCrop) -> Int {
            let centreX = crop.boundingBox.midX
            return Int(centreX / colWidth)
        }

        // Group by column bucket, then sort groups right-to-left, within each
        // group sort top-to-bottom (ascending minY in pixel space).
        let grouped = Dictionary(grouping: crops, by: columnBucket(_:))
        let sortedBuckets = grouped.keys.sorted(by: >)  // right-to-left (higher x first)

        return sortedBuckets.flatMap { bucket in
            (grouped[bucket] ?? []).sorted { $0.boundingBox.minY < $1.boundingBox.minY }
        }
    }

    /// Returns the dynamic column width: the median character width clamped to
    /// [8%, 20%] of the combined horizontal span of all crops.
    func dynamicColumnWidth(_ crops: [CharacterCrop]) -> CGFloat {
        guard !crops.isEmpty else { return 1 }

        let widths = crops.map { $0.boundingBox.width }.sorted()
        let medianWidth = widths[widths.count / 2]

        // Total horizontal span of all crops (used for percentage bounds).
        let allMinX = crops.map { $0.boundingBox.minX }.min() ?? 0
        let allMaxX = crops.map { $0.boundingBox.maxX }.max() ?? 1
        let span = max(allMaxX - allMinX, 1)

        let lower = 0.08 * span
        let upper = 0.20 * span
        return min(max(medianWidth, lower), upper)
    }

    // MARK: - Helpers

    /// Clamps a pixel bounding box so it stays within image bounds.
    func clampedBox(_ box: CGRect, imageWidth: CGFloat, imageHeight: CGFloat) -> CGRect {
        let x = max(0, box.minX)
        let y = max(0, box.minY)
        let maxX = min(imageWidth,  box.maxX)
        let maxY = min(imageHeight, box.maxY)
        guard maxX > x, maxY > y else { return .zero }
        return CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }
}
