import Testing
import UIKit
@testable import NomLens

// MARK: - Helpers

/// Creates a CharacterCrop with only a bounding box (no real image needed for sort tests).
private func crop(x: CGFloat, y: CGFloat, w: CGFloat = 20, h: CGFloat = 20) -> CharacterCrop {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: Int(w), height: Int(h)))
    let img = renderer.image { ctx in
        UIColor.black.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }
    return CharacterCrop(
        id: UUID(),
        image: img,
        boundingBox: CGRect(x: x, y: y, width: w, height: h),
        observationIndex: 0,
        characterIndex: 0,
        normalizedBox: .zero
    )
}

// MARK: - M4: Reading order sort

struct ReadingOrderTests {

    private let seg = CharacterSegmentor()

    /// Two characters in the same column: upper one should come first.
    @Test func singleColumnTopToBottom() {
        let top    = crop(x: 100, y:  10)
        let bottom = crop(x: 100, y:  60)
        let sorted = seg.sortIntoReadingOrder([bottom, top])
        #expect(sorted[0].boundingBox.minY < sorted[1].boundingBox.minY)
    }

    /// Two columns: the right column should come before the left column.
    @Test func twoColumnsRightBeforeLeft() {
        let rightCol = crop(x: 200, y: 10)
        let leftCol  = crop(x:  50, y: 10)
        let sorted   = seg.sortIntoReadingOrder([leftCol, rightCol])
        #expect(sorted[0].boundingBox.midX > sorted[1].boundingBox.midX)
    }

    /// Full 2-column, 2-row grid in correct reading order.
    @Test func twoByTwoGridOrder() {
        // Layout (pixel coords):
        //   (200,10)  (50,10)   ← top row, right col first
        //   (200,60)  (50,60)   ← bottom row
        // Expected order: r0c1, r1c1, r0c0, r1c0
        //   i.e. right column top→bottom, then left column top→bottom
        let r0c1 = crop(x: 200, y: 10)
        let r1c1 = crop(x: 200, y: 60)
        let r0c0 = crop(x:  50, y: 10)
        let r1c0 = crop(x:  50, y: 60)
        let sorted = seg.sortIntoReadingOrder([r0c0, r1c0, r0c1, r1c1])

        #expect(sorted.count == 4)
        // First two should be from the right column (x ≈ 200)
        #expect(sorted[0].boundingBox.midX > 100)
        #expect(sorted[1].boundingBox.midX > 100)
        // Within right column: top before bottom
        #expect(sorted[0].boundingBox.minY < sorted[1].boundingBox.minY)
        // Last two from left column (x ≈ 50)
        #expect(sorted[2].boundingBox.midX < 100)
        #expect(sorted[3].boundingBox.midX < 100)
        #expect(sorted[2].boundingBox.minY < sorted[3].boundingBox.minY)
    }

    @Test func singleCropReturnedUnchanged() {
        let only = crop(x: 100, y: 100)
        #expect(seg.sortIntoReadingOrder([only]).count == 1)
    }

    @Test func emptyCropsReturnedUnchanged() {
        #expect(seg.sortIntoReadingOrder([]).isEmpty)
    }
}

// MARK: - M4: Dynamic column width

struct DynamicColumnWidthTests {

    private let seg = CharacterSegmentor()

    @Test func medianWidthUsedWhenInRange() {
        // Five crops with widths [10, 15, 20, 25, 30], spread x: 0–200
        // span = 200; 8% = 16, 20% = 40; median = 20 → within range → 20
        let crops = [
            crop(x:   0, y: 0, w: 10, h: 20),
            crop(x:  40, y: 0, w: 15, h: 20),
            crop(x:  80, y: 0, w: 20, h: 20),
            crop(x: 120, y: 0, w: 25, h: 20),
            crop(x: 160, y: 0, w: 30, h: 20),
        ]
        let cw = seg.dynamicColumnWidth(crops)
        #expect(abs(cw - 20) < 1, "Expected ~20, got \(cw)")
    }

    @Test func clampedToMinimumWhenMedianTooSmall() {
        // All very narrow (width=1), span = 200 → 8% of 200 = 16
        let crops = (0..<5).map { i in crop(x: CGFloat(i * 40), y: 0, w: 1, h: 20) }
        let cw = seg.dynamicColumnWidth(crops)
        let span: CGFloat = CGFloat((4 * 40) + 1) // maxX - minX
        #expect(cw >= 0.08 * span - 1)
    }

    @Test func clampedToMaximumWhenMedianTooLarge() {
        // All very wide (width=500), span ≈ 500 → 20% of 500 = 100
        let crops = (0..<3).map { i in crop(x: CGFloat(i * 10), y: 0, w: 500, h: 20) }
        let cw = seg.dynamicColumnWidth(crops)
        let span: CGFloat = crops.map { $0.boundingBox.maxX }.max()!
                          - crops.map { $0.boundingBox.minX }.min()!
        #expect(cw <= 0.20 * span + 1)
    }
}

// MARK: - M4: Bounding box clamping

struct ClampedBoxTests {

    private let seg = CharacterSegmentor()

    @Test func inBoundsBoxUnchanged() {
        let box = CGRect(x: 10, y: 10, width: 30, height: 30)
        let clamped = seg.clampedBox(box, imageWidth: 100, imageHeight: 100)
        #expect(clamped == box)
    }

    @Test func leftEdgeClamped() {
        let box = CGRect(x: -5, y: 0, width: 20, height: 20)
        let clamped = seg.clampedBox(box, imageWidth: 100, imageHeight: 100)
        #expect(clamped.minX == 0)
        #expect(clamped.width == 15)
    }

    @Test func rightEdgeClamped() {
        let box = CGRect(x: 90, y: 0, width: 20, height: 20)
        let clamped = seg.clampedBox(box, imageWidth: 100, imageHeight: 100)
        #expect(clamped.maxX == 100)
    }

    @Test func boxCompletelyOutsideReturnsZeroSize() {
        let box = CGRect(x: -50, y: 0, width: 20, height: 20)
        let clamped = seg.clampedBox(box, imageWidth: 100, imageHeight: 100)
        #expect(clamped.width <= 0)
    }
}

// MARK: - M4: SegmentationResult enum

struct SegmentationResultTests {

    @Test func zeroDetectedCase() {
        let r = SegmentationResult.zeroDetected
        if case .zeroDetected = r { } else {
            #expect(Bool(false), "Expected .zeroDetected")
        }
    }

    @Test func belowThresholdCarriesCount() {
        let r = SegmentationResult.belowThreshold(2)
        if case .belowThreshold(let n) = r {
            #expect(n == 2)
        } else {
            #expect(Bool(false), "Expected .belowThreshold")
        }
    }

    @Test func charactersCarriesCrops() {
        let c = crop(x: 0, y: 0)
        let r = SegmentationResult.characters([c])
        if case .characters(let crops) = r {
            #expect(crops.count == 1)
        } else {
            #expect(Bool(false), "Expected .characters")
        }
    }
}
