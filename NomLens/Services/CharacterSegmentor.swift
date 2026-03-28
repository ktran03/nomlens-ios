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

        // Strategy A — Vision line regions + per-line projection.
        // Vision reliably finds TEXT LINE bounding boxes even when its
        // characterBoxes are incomplete. Running column projection within
        // each line is simple and catches characters Vision missed at edges.
        let lineCrops = cropsFromLines(
            observations: observations,
            cgImage: cgImage,
            sourceImage: image
        )

        // Strategy B — full-image projection.
        // Handles vertical column text and images Vision completely ignores
        // (e.g. clean digital characters, very dark/noisy backgrounds).
        let projCrops = projectionSegment(cgImage: cgImage, sourceImage: image)

        print("[NomLens] Segmentor: lineCrops=\(lineCrops.count) projCrops=\(projCrops.count)")

        // Merge both sets — keep everything, deduplicate by bounding-box overlap.
        // This way Vision's line detection and projection complement each other
        // rather than compete.
        let crops = mergeCrops(primary: lineCrops, secondary: projCrops)

        if crops.count < Self.minimumCharacterCount {
            return crops.isEmpty ? .zeroDetected : .belowThreshold(crops.count)
        }
        return .characters(sortIntoReadingOrder(crops))
    }

    // MARK: - Per-line projection

    /// For each Vision-detected text line, binarises the line region and runs
    /// column projection to find individual character columns within it.
    ///
    /// This is more reliable than full-image projection for horizontal layouts
    /// because within a single row there are no cross-row column overlaps, and
    /// the local binarisation handles any background colour automatically.
    private func cropsFromLines(
        observations: [VNTextObservation],
        cgImage: CGImage,
        sourceImage: UIImage
    ) -> [CharacterCrop] {
        let imageW = CGFloat(cgImage.width)
        let imageH = CGFloat(cgImage.height)
        var result  = [CharacterCrop]()

        for (obsIdx, obs) in observations.enumerated() {
            // Vision uses bottom-left origin with y increasing upward.
            let norm    = obs.boundingBox
            let lineBox = CGRect(
                x:      norm.minX * imageW,
                y:      (1 - norm.maxY) * imageH,
                width:  norm.width  * imageW,
                height: norm.height * imageH
            )
            let lineClamped = clampedBox(lineBox, imageWidth: imageW, imageHeight: imageH)
            guard lineClamped.width >= 20, lineClamped.height >= 20,
                  let lineCG = cgImage.cropping(to: lineClamped) else { continue }

            let lw = lineCG.width
            let lh = lineCG.height

            // Greyscale bitmap for this line region.
            var pixels = [UInt8](repeating: 255, count: lw * lh)
            guard let ctx = CGContext(
                data: &pixels, width: lw, height: lh,
                bitsPerComponent: 8, bytesPerRow: lw,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { continue }
            ctx.draw(lineCG, in: CGRect(x: 0, y: 0, width: lw, height: lh))
            localBinarize(pixels: &pixels, width: lw, height: lh)

            // Column projection within this line.
            var colInk = [Int](repeating: 0, count: lw)
            for y in 0 ..< lh {
                let base = y * lw
                for x in 0 ..< lw where pixels[base + x] < 128 { colInk[x] += 1 }
            }

            let charCols = characterRanges(projection: colInk, crossExtent: lh, totalSize: lw)

            for (charIdx, col) in charCols.enumerated() {
                let pad = 2
                let x0  = max(0, col.lowerBound - pad)
                let x1  = min(lw, col.upperBound  + pad)

                // Map back to full-image pixel space.
                let fullBox = CGRect(
                    x:      lineClamped.minX + CGFloat(x0),
                    y:      lineClamped.minY,
                    width:  CGFloat(x1 - x0),
                    height: lineClamped.height
                )
                let fullClamped = clampedBox(fullBox, imageWidth: imageW, imageHeight: imageH)
                guard fullClamped.width >= 20, fullClamped.height >= 20 else { continue }
                guard let cropCG = cgImage.cropping(to: fullClamped) else { continue }

                let cropUI = UIImage(cgImage: cropCG, scale: sourceImage.scale,
                                     orientation: sourceImage.imageOrientation)
                let normBox = CGRect(
                    x:      fullClamped.minX / imageW,
                    y:      1 - fullClamped.maxY / imageH,
                    width:  fullClamped.width  / imageW,
                    height: fullClamped.height / imageH
                )
                result.append(CharacterCrop(
                    id: UUID(), image: cropUI,
                    boundingBox: fullClamped,
                    observationIndex: obsIdx,
                    characterIndex: charIdx,
                    normalizedBox: normBox
                ))
            }
        }
        return result
    }

    /// Merges two crop sets, adding crops from `secondary` only when they do
    /// not overlap significantly (IoU > 0.3) with any crop already in `primary`.
    private func mergeCrops(primary: [CharacterCrop], secondary: [CharacterCrop]) -> [CharacterCrop] {
        var merged = primary
        for crop in secondary {
            let duplicate = merged.contains { existing in
                let inter = existing.boundingBox.intersection(crop.boundingBox)
                guard !inter.isNull, !inter.isEmpty else { return false }
                let smaller = min(
                    existing.boundingBox.width * existing.boundingBox.height,
                    crop.boundingBox.width     * crop.boundingBox.height
                )
                guard smaller > 0 else { return false }
                return (inter.width * inter.height) / smaller > 0.3
            }
            if !duplicate { merged.append(crop) }
        }
        return merged
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
    func sortIntoReadingOrder(_ crops: [CharacterCrop]) -> [CharacterCrop] {
        guard crops.count > 1 else { return crops }

        let colWidth = dynamicColumnWidth(crops)

        func columnBucket(_ crop: CharacterCrop) -> Int {
            return Int(crop.boundingBox.midX / colWidth)
        }

        let grouped      = Dictionary(grouping: crops, by: columnBucket(_:))
        let sortedBuckets = grouped.keys.sorted(by: >)

        return sortedBuckets.flatMap { bucket in
            (grouped[bucket] ?? []).sorted { $0.boundingBox.minY < $1.boundingBox.minY }
        }
    }

    /// Returns the dynamic column width: the median character width clamped to
    /// [8%, 20%] of the combined horizontal span of all crops.
    func dynamicColumnWidth(_ crops: [CharacterCrop]) -> CGFloat {
        guard !crops.isEmpty else { return 1 }

        let widths      = crops.map { $0.boundingBox.width }.sorted()
        let medianWidth = widths[widths.count / 2]

        let allMinX = crops.map { $0.boundingBox.minX }.min() ?? 0
        let allMaxX = crops.map { $0.boundingBox.maxX }.max() ?? 1
        let span    = max(allMaxX - allMinX, 1)

        return min(max(medianWidth, 0.08 * span), 0.20 * span)
    }

    // MARK: - Projection-based segmentation
    //
    // Two modes are tried automatically:
    //
    // Grid-border mode — for documents with printed borders between cells
    // (e.g. traditional printed books). Narrow, high-density ink bands are
    // treated as grid lines; the gaps between them become character cells.
    //
    // Gap mode — for plain column text without borders. Ink-positive bands
    // separated by white-space become character columns; row projection within
    // each column yields individual character rows.
    //
    // The mode is selected per-axis independently, so a document can have
    // vertical grid lines but not horizontal ones (or vice versa).

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

        // Binarize using Otsu's global threshold.
        let otsu = adaptiveThreshold(pixels: pixels)
        for i in pixels.indices { pixels[i] = pixels[i] < otsu ? 0 : 255 }
        let threshold = UInt8(128)   // pixels are now 0 or 255

        // Build column and row projections in one pass.
        var colInk = [Int](repeating: 0, count: w)
        var rowInk = [Int](repeating: 0, count: h)
        for y in 0 ..< h {
            let base = y * w
            for x in 0 ..< w where pixels[base + x] < threshold {
                colInk[x] += 1
                rowInk[y] += 1
            }
        }

        // Column ranges — grid-border mode or gap mode chosen automatically.
        let colRanges = characterRanges(projection: colInk, crossExtent: h, totalSize: w)

        // Row-first fallback: if any column band is suspiciously wide
        // (wider than 1/3 of image width), columns were likely merged.
        // Try rows first, then columns within each row.
        let maxColWidth = colRanges.map(\.count).max() ?? 0
        if maxColWidth > w / 3 {
            var rowRangesTop = characterRanges(projection: rowInk, crossExtent: w, totalSize: h)
            // Valley-split any row band taller than 60 % of image height.
            rowRangesTop = splitWideBands(projection: rowInk, bands: rowRangesTop,
                                          maxWidth: h * 6 / 10, peakFraction: 0.65)
            if rowRangesTop.count >= 2 {
                var rowFirstCrops: [CharacterCrop] = []
                for (rowIdx, rowRange) in rowRangesTop.enumerated() {
                    var rowColInk = [Int](repeating: 0, count: w)
                    for y in rowRange {
                        let base = y * w
                        for x in 0 ..< w where pixels[base + x] < threshold { rowColInk[x] += 1 }
                    }
                    var subColRanges = characterRanges(
                        projection: rowColInk,
                        crossExtent: rowRange.count,
                        totalSize: w
                    )
                    // Valley-split any column band wider than 30 % of image width.
                    subColRanges = splitWideBands(projection: rowColInk, bands: subColRanges,
                                                  maxWidth: w * 3 / 10, peakFraction: 0.65)
                    for (colIdx, colRange) in subColRanges.enumerated() {
                        let pad = 3
                        let x0 = max(0, colRange.lowerBound - pad)
                        let y0 = max(0, rowRange.lowerBound - pad)
                        let x1 = min(w, colRange.upperBound  + pad)
                        let y1 = min(h, rowRange.upperBound  + pad)
                        let pixelBox = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                        let clamped  = clampedBox(pixelBox, imageWidth: CGFloat(w), imageHeight: CGFloat(h))
                        guard clamped.width >= 20, clamped.height >= 20 else { continue }
                        guard cellHasInk(in: clamped, pixels: pixels, imageWidth: w, threshold: threshold) else { continue }
                        guard let croppedCG = cgImage.cropping(to: clamped) else { continue }
                        let cropUI = UIImage(cgImage: croppedCG, scale: sourceImage.scale,
                                             orientation: sourceImage.imageOrientation)
                        let norm = CGRect(
                            x:      clamped.minX / CGFloat(w),
                            y:      1 - clamped.maxY / CGFloat(h),
                            width:  clamped.width  / CGFloat(w),
                            height: clamped.height / CGFloat(h)
                        )
                        rowFirstCrops.append(CharacterCrop(
                            id: UUID(), image: cropUI, boundingBox: clamped,
                            observationIndex: rowIdx, characterIndex: colIdx,
                            normalizedBox: norm
                        ))
                    }
                }
                if rowFirstCrops.count > 1 { return rowFirstCrops }
            }
        }

        guard !colRanges.isEmpty else { return [] }

        var crops: [CharacterCrop] = []

        for (colIdx, colRange) in colRanges.enumerated() {
            // Row projection scoped to this column band.
            var colRowInk = [Int](repeating: 0, count: h)
            for y in 0 ..< h {
                let base = y * w
                for x in colRange where pixels[base + x] < threshold {
                    colRowInk[y] += 1
                }
            }

            let rowRanges = characterRanges(
                projection: colRowInk,
                crossExtent: colRange.count,
                totalSize: h
            )

            for (rowIdx, rowRange) in rowRanges.enumerated() {
                let pad = 3
                let x0 = max(0, colRange.lowerBound - pad)
                let y0 = max(0, rowRange.lowerBound - pad)
                let x1 = min(w, colRange.upperBound  + pad)
                let y1 = min(h, rowRange.upperBound  + pad)

                let pixelBox = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                let clamped  = clampedBox(pixelBox, imageWidth: CGFloat(w), imageHeight: CGFloat(h))
                guard clamped.width >= 20, clamped.height >= 20 else { continue }

                // Discard nearly-empty cells (empty grid slots, margins, noise).
                guard cellHasInk(in: clamped, pixels: pixels, imageWidth: w, threshold: threshold)
                else { continue }

                guard let croppedCG = cgImage.cropping(to: clamped) else { continue }
                let cropUI = UIImage(cgImage: croppedCG,
                                     scale: sourceImage.scale,
                                     orientation: sourceImage.imageOrientation)
                let norm = CGRect(
                    x:      clamped.minX / CGFloat(w),
                    y:      1 - clamped.maxY / CGFloat(h),
                    width:  clamped.width  / CGFloat(w),
                    height: clamped.height / CGFloat(h)
                )
                crops.append(CharacterCrop(
                    id: UUID(),
                    image: cropUI,
                    boundingBox: clamped,
                    observationIndex: colIdx,
                    characterIndex: rowIdx,
                    normalizedBox: norm
                ))
            }
        }
        return crops
    }

    // MARK: - Character range detection

    /// Detects character cell extents along one axis of a projection array.
    ///
    /// **Grid-border mode** is used when ≥ 3 narrow high-density bands are found
    /// — these are treated as grid lines and the cells are the gaps between them.
    ///
    /// **Gap mode** is used otherwise — ink-positive bands with small minGap.
    ///
    /// - projection:  ink counts per pixel along this axis
    /// - crossExtent: image size in the perpendicular direction
    ///                (height for column projection; column width for row projection)
    /// - totalSize:   length of the `projection` array
    private func characterRanges(
        projection: [Int],
        crossExtent: Int,
        totalSize:   Int
    ) -> [Range<Int>] {
        guard !projection.isEmpty else { return [] }

        // Noise floor: projection values below 10% of the peak are treated as
        // background. This is essential for aged/coloured paper where the
        // background texture creates low-level ink counts in every gap, which
        // would otherwise merge all character bands into a single blob.
        let peak       = projection.max() ?? 1
        // Noise floor at ~17 % of peak so that stroke halos in gap regions
        // (typically 10-15 % of peak on aged/coloured backgrounds) are treated
        // as background, not ink.  Still low enough to catch faint characters.
        let noiseFloor = peak / 6

        let gridlineMaxWidth   = max(4, totalSize / 100)
        let gridlineMinDensity = crossExtent * 75 / 100

        let rawBands  = inkBands(in: projection, minGap: 1, minValue: noiseFloor)
        let gridlines = rawBands.filter { band in
            guard band.count <= gridlineMaxWidth else { return false }
            let mid = (band.lowerBound + band.upperBound) / 2
            return projection[mid] >= gridlineMinDensity
        }

        if gridlines.count >= 3 {
            let minCell = max(15, gridlineMaxWidth * 3)
            return gapsBetween(gridlines, total: totalSize, minSize: minCell)
        } else {
            let minGap = max(2, totalSize / 200)
            return inkBands(in: projection, minGap: minGap, minValue: noiseFloor)
        }
    }

    /// Returns the white-space intervals between consecutive sorted bands.
    private func gapsBetween(_ bands: [Range<Int>], total: Int, minSize: Int) -> [Range<Int>] {
        let sorted = bands.sorted { $0.lowerBound < $1.lowerBound }
        var result  = [Range<Int>]()
        var cursor  = 0
        for band in sorted {
            if band.lowerBound - cursor >= minSize {
                result.append(cursor ..< band.lowerBound)
            }
            cursor = band.upperBound
        }
        if total - cursor >= minSize {
            result.append(cursor ..< total)
        }
        return result
    }

    // MARK: - inkBands

    /// Returns contiguous index ranges where `values[i] > minValue`, merging runs
    /// whose gap to the next run is smaller than `minGap`.
    private func inkBands(in values: [Int], minGap: Int, minValue: Int = 0) -> [Range<Int>] {
        var raw: [Range<Int>] = []
        var start: Int? = nil
        for (i, v) in values.enumerated() {
            if v > minValue {
                if start == nil { start = i }
            } else if let s = start {
                raw.append(s ..< i)
                start = nil
            }
        }
        if let s = start { raw.append(s ..< values.count) }

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

    // MARK: - Valley splitting

    /// Splits `band` at its deepest valley if the valley dips below
    /// `peakFraction` of the smoothed peak inside that band.
    /// Returns the original single-element array if no qualifying valley exists.
    ///
    /// Useful when characters are close enough that the gap projection never
    /// reaches the noise floor, but still has a clear local minimum between them.
    private func splitAtDeepestValley(
        projection: [Int],
        band: Range<Int>,
        peakFraction: Double = 0.65,
        label: String = ""
    ) -> [Range<Int>] {
        let count = band.count
        guard count > 20 else { return [band] }

        // Smooth to suppress per-pixel noise.
        let win = max(3, count / 20)
        let half = win / 2
        var smoothed = [Double](repeating: 0, count: count)
        for i in 0 ..< count {
            var sum = 0.0; var cnt = 0
            for j in max(0, i - half) ... min(count - 1, i + half) {
                sum += Double(projection[band.lowerBound + j]); cnt += 1
            }
            smoothed[i] = cnt > 0 ? sum / Double(cnt) : 0
        }

        let peakVal  = smoothed.max() ?? 0
        guard peakVal > 0 else { return [band] }
        let valThresh = peakVal * peakFraction

        // Search the middle 60 % of the band to avoid edge artifacts.
        let margin = max(1, count / 5)
        var deepestIdx = -1
        var deepestVal = Double.infinity
        for i in margin ..< (count - margin) {
            if smoothed[i] < valThresh && smoothed[i] < deepestVal {
                deepestVal = smoothed[i]; deepestIdx = i
            }
        }

        guard deepestIdx > 0 else {
            print("[Seg] valleySplit\(label.isEmpty ? "" : "[\(label)]"): no valley below \(Int(valThresh)) (peak=\(Int(peakVal)))")
            return [band]
        }
        let splitAt = band.lowerBound + deepestIdx
        print("[Seg] valleySplit\(label.isEmpty ? "" : "[\(label)]"): split \(band) at \(splitAt), valley=\(Int(deepestVal))/\(Int(peakVal)) (\(Int(deepestVal*100/peakVal))% of peak)")
        return [band.lowerBound ..< splitAt, splitAt ..< band.upperBound]
    }

    /// Iteratively splits bands that are wider than `maxWidth` at their
    /// deepest valley, up to `maxPasses` rounds.
    private func splitWideBands(
        projection: [Int],
        bands: [Range<Int>],
        maxWidth: Int,
        peakFraction: Double = 0.65,
        maxPasses: Int = 3,
        label: String = ""
    ) -> [Range<Int>] {
        var result = bands
        for pass in 0 ..< maxPasses {
            var changed = false
            var next: [Range<Int>] = []
            for band in result {
                if band.count > maxWidth {
                    let sub = splitAtDeepestValley(projection: projection, band: band,
                                                   peakFraction: peakFraction,
                                                   label: "\(label)p\(pass)")
                    if sub.count > 1 { changed = true; next.append(contentsOf: sub); continue }
                }
                next.append(band)
            }
            result = next
            if !changed { break }
        }
        return result
    }

    // MARK: - Pixel helpers

    /// Local block adaptive binarization.
    ///
    /// Divides the image into blocks and thresholds each pixel against 85% of
    /// its block's mean intensity. Pixels darker than the local mean → 0 (black);
    /// everything else → 255 (white).
    ///
    /// This is robust to any background colour or uneven illumination because
    /// each block normalises against its own local brightness, not a global value.
    /// Block size is ~1/6 of the shorter image dimension (large enough to span
    /// several characters so the mean isn't skewed by a single character's ink).
    private func localBinarize(pixels: inout [UInt8], width: Int, height: Int) {
        let blockSize = max(32, min(width, height) / 6)
        var blockY = 0
        while blockY < height {
            var blockX = 0
            while blockX < width {
                let x0 = blockX; let x1 = min(blockX + blockSize, width)
                let y0 = blockY; let y1 = min(blockY + blockSize, height)

                // Mean intensity of this block
                var sum = 0
                for y in y0 ..< y1 {
                    let base = y * width
                    for x in x0 ..< x1 { sum += Int(pixels[base + x]) }
                }
                let count = (x1 - x0) * (y1 - y0)
                let mean  = count > 0 ? sum / count : 128
                // Threshold at 85 % of mean: pixels noticeably darker than the
                // local background are ink; everything brighter is background.
                let t = UInt8(clamping: mean * 85 / 100)

                for y in y0 ..< y1 {
                    let base = y * width
                    for x in x0 ..< x1 {
                        pixels[base + x] = pixels[base + x] < t ? 0 : 255
                    }
                }
                blockX += blockSize
            }
            blockY += blockSize
        }
    }

    /// Otsu's method: finds the greyscale threshold that maximally separates
    /// ink (dark) from background (light) using the pixel intensity histogram.
    /// Works on any background colour — white paper, yellowed paper, stone, etc.
    private func adaptiveThreshold(pixels: [UInt8]) -> UInt8 {
        guard pixels.count > 0 else { return 128 }

        // Build histogram
        var hist = [Int](repeating: 0, count: 256)
        for p in pixels { hist[Int(p)] += 1 }

        let total = pixels.count
        var sumAll = 0
        for i in 0..<256 { sumAll += i * hist[i] }

        var sumDark = 0, wDark = 0
        var bestVar = 0.0
        var threshold = UInt8(128)

        for t in 0..<256 {
            wDark += hist[t]
            guard wDark > 0 else { continue }
            let wLight = total - wDark
            guard wLight > 0 else { break }

            sumDark += t * hist[t]
            let meanDark  = Double(sumDark) / Double(wDark)
            let meanLight = Double(sumAll - sumDark) / Double(wLight)
            let between   = Double(wDark) * Double(wLight) * (meanDark - meanLight) * (meanDark - meanLight)

            if between > bestVar {
                bestVar   = between
                threshold = UInt8(t)
            }
        }
        return threshold
    }

    /// Returns true if ≥ 4 % of pixels in `rect` are below the ink threshold.
    /// Early-exits as soon as the quota is reached for performance.
    private func cellHasInk(
        in rect: CGRect,
        pixels: [UInt8],
        imageWidth: Int,
        threshold: UInt8
    ) -> Bool {
        let x0 = Int(rect.minX); let x1 = min(Int(rect.maxX), imageWidth)
        let y0 = Int(rect.minY); let y1 = Int(rect.maxY)
        let area = (x1 - x0) * (y1 - y0)
        guard area > 0 else { return false }
        let needed = max(1, area * 4 / 100)
        var ink = 0
        for y in y0 ..< y1 {
            let base = y * imageWidth
            for x in x0 ..< x1 {
                if pixels[base + x] < threshold {
                    ink += 1
                    if ink >= needed { return true }
                }
            }
        }
        return false
    }

    /// Clamps a pixel bounding box so it stays within image bounds.
    func clampedBox(_ box: CGRect, imageWidth: CGFloat, imageHeight: CGFloat) -> CGRect {
        let x    = max(0, box.minX)
        let y    = max(0, box.minY)
        let maxX = min(imageWidth,  box.maxX)
        let maxY = min(imageHeight, box.maxY)
        guard maxX > x, maxY > y else { return .zero }
        return CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }
}
