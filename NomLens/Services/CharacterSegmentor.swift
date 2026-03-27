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
        guard let cgImage = image.cgImage else {
            return .zeroDetected
        }

        let observations = await runVision(on: cgImage)

        if observations.isEmpty {
            // Vision found nothing — fall back to projection-based blob detection.
            // This handles clean/digital images (e.g. 人, 雨) where Vision expects
            // photographic texture and returns no observations.
            let crops = projectionSegment(cgImage: cgImage, sourceImage: image)
            if crops.count < Self.minimumCharacterCount {
                return crops.isEmpty ? .zeroDetected : .belowThreshold(crops.count)
            }
            let sorted = sortIntoReadingOrder(crops)
            return .characters(sorted)
        }

        let crops = buildCrops(from: observations, sourceImage: image, cgImage: cgImage)

        if crops.count < Self.minimumCharacterCount {
            return .belowThreshold(crops.count)
        }

        let sorted = sortIntoReadingOrder(crops)
        return .characters(sorted)
    }

    // MARK: - Vision
    //
    // VNDetectTextRectanglesRequest does script-agnostic region detection —
    // it finds ink blobs shaped like characters without a language model,
    // making it suitable for Han Nôm.
    //
    // However it is tuned for "document-scale" text. Very large characters
    // (e.g. digital mock-ups or close-up crops) need to be scaled down first
    // so the text appears at a density the detector recognises. We try at
    // full scale, then at 50 % and 25 % if no observations are returned.

    /// Target longest-side length used for Vision detection.
    private static let detectionMaxDimension: CGFloat = 800

    private func runVision(on cgImage: CGImage) async -> [VNTextObservation] {
        // Build a candidate list of scales to try. Start at a normalised size
        // (≤ detectionMaxDimension), then fall back to halved versions.
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let baseScale = min(1.0, Self.detectionMaxDimension / max(w, h))
        let scales: [CGFloat] = [baseScale, baseScale * 0.5, baseScale * 0.25]

        for scale in scales {
            let target = scale == 1.0 ? cgImage : scaled(cgImage, by: scale)
            guard let img = target else { continue }
            let obs = await detectTextRectangles(in: img)
            if !obs.isEmpty { return obs }
        }
        return []
    }

    private func detectTextRectangles(in cgImage: CGImage) async -> [VNTextObservation] {
        await withCheckedContinuation { continuation in
            let request = VNDetectTextRectanglesRequest { request, _ in
                let obs = request.results as? [VNTextObservation] ?? []
                continuation.resume(returning: obs)
            }
            request.reportCharacterBoxes = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    /// Returns a scaled copy of `cgImage`. Returns nil if the context can't be made.
    private func scaled(_ cgImage: CGImage, by scale: CGFloat) -> CGImage? {
        let newW = max(1, Int(CGFloat(cgImage.width)  * scale))
        let newH = max(1, Int(CGFloat(cgImage.height) * scale))
        guard let ctx = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage()
    }

    // MARK: - Crop extraction

    private func buildCrops(
        from observations: [VNTextObservation],
        sourceImage: UIImage,
        cgImage: CGImage
    ) -> [CharacterCrop] {
        let imageW = CGFloat(cgImage.width)
        let imageH = CGFloat(cgImage.height)

        var crops: [CharacterCrop] = []

        for (obsIdx, obs) in observations.enumerated() {
            // characterBoxes contains one VNRectangleObservation per detected glyph.
            let charBoxes = obs.characterBoxes ?? []

            for (charIdx, box) in charBoxes.enumerated() {
                // Vision normalized box: origin bottom-left, y increases upward.
                // Convert to pixel-space with origin top-left.
                let norm = box.boundingBox
                let pixelBox = CGRect(
                    x:      norm.minX * imageW,
                    y:      (1 - norm.maxY) * imageH,
                    width:  norm.width  * imageW,
                    height: norm.height * imageH
                )

                let clamped = clampedBox(pixelBox, imageWidth: imageW, imageHeight: imageH)
                // Skip fragments too small to contain a legible character.
                // Han Nôm glyphs need at least 20×20 px to be identifiable.
                guard clamped.width >= 20, clamped.height >= 20 else { continue }

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

    // MARK: - Projection-based fallback

    /// Fallback segmentor for clean / digital images where Vision returns nothing.
    ///
    /// Algorithm:
    ///  1. Render the image into a greyscale 8-bit bitmap (CGContext — thread-safe).
    ///  2. Threshold each pixel as "ink" (dark) or "background" (light).
    ///  3. Column projection → contiguous ink bands → character column extents.
    ///  4. Row projection within each column band → character row extents.
    ///  5. Build `CharacterCrop` for every (column band × row band) cell.
    private func projectionSegment(cgImage: CGImage, sourceImage: UIImage) -> [CharacterCrop] {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return [] }

        // Greyscale bitmap — one byte per pixel, no alpha.
        var pixels = [UInt8](repeating: 255, count: w * h)
        guard let ctx = CGContext(
            data: &pixels,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return [] }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Dark pixel = value < threshold.
        let threshold: UInt8 = 180

        // Column projection.
        var colInk = [Int](repeating: 0, count: w)
        for y in 0 ..< h {
            let row = y * w
            for x in 0 ..< w where pixels[row + x] < threshold {
                colInk[x] += 1
            }
        }

        // Minimum gap between separate characters: ~4 % of image width (≥ 2 px).
        let minGap = max(2, w / 25)
        let colBands = inkBands(in: colInk, minGap: minGap)
        guard !colBands.isEmpty else { return [] }

        var crops: [CharacterCrop] = []

        for (bandIdx, colBand) in colBands.enumerated() {
            // Row projection within this column band.
            var rowInk = [Int](repeating: 0, count: h)
            for y in 0 ..< h {
                let row = y * w
                for x in colBand where pixels[row + x] < threshold {
                    rowInk[y] += 1
                }
            }
            let rowBands = inkBands(in: rowInk, minGap: minGap)

            for (charIdx, rowBand) in rowBands.enumerated() {
                let pad = 4
                let x0 = max(0, colBand.lowerBound - pad)
                let y0 = max(0, rowBand.lowerBound - pad)
                let x1 = min(w, colBand.upperBound + pad)
                let y1 = min(h, rowBand.upperBound + pad)

                let pixelBox = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                let clamped  = clampedBox(pixelBox, imageWidth: CGFloat(w), imageHeight: CGFloat(h))
                guard clamped.width >= 20, clamped.height >= 20 else { continue }

                guard let croppedCG = cgImage.cropping(to: clamped) else { continue }
                let cropUI = UIImage(cgImage: croppedCG,
                                     scale: sourceImage.scale,
                                     orientation: sourceImage.imageOrientation)
                let norm = CGRect(
                    x:      clamped.minX / CGFloat(w),
                    y:      1 - clamped.maxY / CGFloat(h),   // Vision bottom-left convention
                    width:  clamped.width  / CGFloat(w),
                    height: clamped.height / CGFloat(h)
                )
                crops.append(CharacterCrop(
                    id: UUID(),
                    image: cropUI,
                    boundingBox: clamped,
                    observationIndex: bandIdx,
                    characterIndex: charIdx,
                    normalizedBox: norm
                ))
            }
        }
        return crops
    }

    /// Returns contiguous index ranges where `values[i] > 0`, merging runs
    /// whose gap to the next run is smaller than `minGap`.
    private func inkBands(in values: [Int], minGap: Int) -> [Range<Int>] {
        var raw: [Range<Int>] = []
        var start: Int? = nil
        for (i, v) in values.enumerated() {
            if v > 0 {
                if start == nil { start = i }
            } else if let s = start {
                raw.append(s ..< i)
                start = nil
            }
        }
        if let s = start { raw.append(s ..< values.count) }

        // Merge nearby bands.
        var merged: [Range<Int>] = []
        for band in raw {
            if let last = merged.last, band.lowerBound - last.upperBound < minGap {
                merged[merged.count - 1] = last.lowerBound ..< band.upperBound
            } else {
                merged.append(band)
            }
        }
        return merged
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
