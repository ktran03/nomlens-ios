import UIKit
import CoreImage
import ImageIO

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
    ///
    /// UIKit's `jpegData` can return nil for CGImage-backed images with device color
    /// spaces when called off the main thread. Falls back to ImageIO, then to a
    /// manual sRGB bitmap re-render as a last resort.
    static func base64JPEG(from image: UIImage, quality: CGFloat = 0.9) -> String? {
        // Primary path — works when called on the main thread
        if let data = image.jpegData(compressionQuality: quality) {
            return data.base64EncodedString()
        }
        // ImageIO fallback — thread-safe, accepts most CGImage color spaces
        if let cgImage = image.cgImage,
           let encoded = jpegViaImageIO(cgImage: cgImage, quality: quality) {
            return encoded
        }
        // Last resort: re-render into a standard sRGB bitmap then encode.
        // Core Image pipelines can produce CGImages with extended-range or
        // working color spaces that neither UIKit nor ImageIO can JPEG-encode.
        guard let cgImage = image.cgImage,
              let srgb = rerenderedSRGB(cgImage),
              let encoded = jpegViaImageIO(cgImage: srgb, quality: quality) else {
            return nil
        }
        return encoded
    }

    /// Encodes a CGImage to base64 JPEG via ImageIO (thread-safe).
    private static func jpegViaImageIO(cgImage: CGImage, quality: CGFloat) -> String? {
        let buf = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            buf, "public.jpeg" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            dest, cgImage,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else { return nil }
        return buf.base64EncodedString()
    }

    /// Re-renders a CGImage into a standard sRGB 8-bit bitmap context.
    /// This normalizes any extended-range or non-standard color space that
    /// the JPEG encoder cannot handle.
    private static func rerenderedSRGB(_ source: CGImage) -> CGImage? {
        let w = source.width
        let h = source.height
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: w,
                  height: h,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: srgb,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
