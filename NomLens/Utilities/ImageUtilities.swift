import UIKit
import CoreImage

/// Conversion helpers between `CIImage`, `CGImage`, and `UIImage`.
/// Used throughout the preprocessing and segmentation pipeline.
enum ImageUtilities {

    // MARK: - CIImage conversions

    static func ciImage(from uiImage: UIImage) -> CIImage? {
        if let ci = uiImage.ciImage { return ci }
        guard let cg = uiImage.cgImage else { return nil }
        return CIImage(cgImage: cg)
    }

    static func cgImage(from ciImage: CIImage, context: CIContext? = nil) -> CGImage? {
        let ctx = context ?? CIContext()
        return ctx.createCGImage(ciImage, from: ciImage.extent)
    }

    static func uiImage(from ciImage: CIImage, context: CIContext? = nil) -> UIImage? {
        guard let cg = cgImage(from: ciImage, context: context) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - JPEG helpers

    /// Encodes a `UIImage` to JPEG data at the given quality (0–1).
    static func jpegData(from image: UIImage, quality: CGFloat = 0.9) -> Data? {
        image.jpegData(compressionQuality: quality)
    }

    /// Returns a base64-encoded JPEG string suitable for the Claude API `image` block.
    static func base64JPEG(from image: UIImage, quality: CGFloat = 0.9) -> String? {
        jpegData(from: image, quality: quality)?.base64EncodedString()
    }
}
