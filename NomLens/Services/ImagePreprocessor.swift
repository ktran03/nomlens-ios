import CoreImage
import UIKit

/// Runs a configurable Core Image filter pipeline on an input image.
/// All processing is GPU-accelerated via the injected `CIContext`.
///
/// Filter order matters — see `process(image:settings:)` for rationale.
struct ImagePreprocessor {

    let context: CIContext

    init(context: CIContext = CIContext()) {
        self.context = context
    }

    // MARK: - Pipeline

    /// Apply the full preprocessing pipeline in the correct order:
    /// perspective → deskew → noise reduction → tone → adaptive threshold → sharpen.
    func process(image: CIImage, settings: PreprocessingSettings) -> CIImage {
        var out = image

        // 1. Perspective correction — must come first so all subsequent filters
        //    work on a geometry-corrected image.
        if settings.perspectiveCorrectionEnabled {
            out = applyPerspectiveCorrection(out, quad: settings.perspectiveQuad)
        }

        // 2. Deskew — remove residual rotation after perspective fix.
        if settings.deskewEnabled {
            out = out.applyingFilter("CIStraightenFilter", parameters: [
                "inputAngle": settings.straightenAngle
            ])
        }

        // 3. Noise reduction — before contrast boost so we don't amplify noise.
        if settings.noiseReductionEnabled {
            out = out.applyingFilter("CINoiseReduction", parameters: [
                "inputNoiseLevel": settings.noiseLevel,
                "inputSharpness":  settings.noiseSharpness
            ])
        }

        // 4. Contrast / brightness / desaturate — grayscale conversion happens here
        //    (saturation forced to 0). Must precede adaptive threshold.
        out = out.applyingFilter("CIColorControls", parameters: [
            "inputContrast":    settings.contrast,
            "inputBrightness":  settings.brightness,
            "inputSaturation":  Float(0)
        ])

        // 5. Adaptive threshold — critical for steles with uneven illumination.
        //    Operates on the desaturated image from step 4.
        if settings.adaptiveThresholdEnabled {
            out = applyAdaptiveThreshold(out, bias: settings.thresholdBias)
        }

        // 6. Sharpen — last so we enhance the final edges, not intermediate noise.
        if settings.sharpenEnabled {
            out = out.applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius":    settings.sharpenRadius,
                "inputIntensity": settings.sharpenIntensity
            ])
        }

        return out
    }

    // MARK: - Adaptive Threshold

    /// Local-contrast adaptive thresholding using Core Image filter composition.
    ///
    /// Core Image has no native adaptive threshold, so we compose it:
    ///   1. Gaussian blur (radius 21) → local mean B
    ///   2. Compute 0.5·(original − B) + 0.5 + bias
    ///      — always in [bias, 1+bias], never goes negative for |bias| ≤ 0.2
    ///      — values > 0.5+bias → pixel is brighter than local mean → white
    ///      — values < 0.5+bias → pixel is darker than local mean → black
    ///   3. High-contrast CIColorControls pushes the result to hard 0/1
    ///
    /// Anti-aliased edges are expected and valid on real damaged images.
    /// - Parameter blurRadius: Gaussian blur radius for computing the local mean.
    ///   Default 21.0 is appropriate for full-size field photos. Pass a smaller
    ///   value (e.g. 5.0) when calling from tests with small synthetic images —
    ///   a radius larger than ~1/3 of the image dimension causes boundary bleeding
    ///   that makes every pixel appear above its local mean.
    func applyAdaptiveThreshold(_ image: CIImage, bias: Float, blurRadius: Double = 21.0) -> CIImage {
        let extent = image.extent

        // Step 1: local mean via heavy Gaussian blur
        let blurred = image
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": blurRadius])
            .cropped(to: extent)

        // Step 2a: scale original → 0.5 · original, alpha unchanged.
        // inputAVector explicitly set to identity; inputBiasVector.w = 0
        // so alpha is not modified (w:1 in biasVector would add 1.0 to alpha,
        // producing alpha=2 which corrupts premultiplied rendering).
        let halfOriginal = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector":    CIVector(x: 0.5, y: 0,   z: 0,   w: 0),
            "inputGVector":    CIVector(x: 0,   y: 0.5, z: 0,   w: 0),
            "inputBVector":    CIVector(x: 0,   y: 0,   z: 0.5, w: 0),
            "inputAVector":    CIVector(x: 0,   y: 0,   z: 0,   w: 1),
            "inputBiasVector": CIVector(x: 0,   y: 0,   z: 0,   w: 0)
        ])

        // Step 2b: scale blurred → −0.5·blurred + 0.5 (bias-free).
        // Bias is NOT included here — it's applied as a separate additive shift
        // in step 3a so it cannot cancel out inside the threshold formula.
        let halfInvBlurred = blurred.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector":    CIVector(x: -0.5, y: 0,    z: 0,    w: 0),
            "inputGVector":    CIVector(x: 0,    y: -0.5, z: 0,    w: 0),
            "inputBVector":    CIVector(x: 0,    y: 0,    z: -0.5, w: 0),
            "inputAVector":    CIVector(x: 0,    y: 0,    z: 0,    w: 1),
            "inputBiasVector": CIVector(x: 0.5,  y: 0.5,  z: 0.5,  w: 0)
        ])

        // Step 2c: combined = 0.5·(original − blurred) + 0.5  (always in [0,1])
        let combined = halfOriginal
            .applyingFilter("CIAdditionCompositing", parameters: [
                "inputBackgroundImage": halfInvBlurred
            ])
            .cropped(to: extent)

        // Step 3: threshold.
        // combined = 0.5*(original−blurred) + 0.5, so at-mean pixels land at 0.5.
        // brightness = −0.5 + bias shifts the effective zero point:
        //   output ≈ (combined − 0.5 + bias) * 50 = (0.5*(o−b) + bias) * 50
        // bias > 0 → more pixels go white; bias < 0 → more pixels go black.
        return combined.applyingFilter("CIColorControls", parameters: [
            "inputContrast":   Float(50.0),
            "inputBrightness": Float(-0.5 + Double(bias))
        ])
    }

    // MARK: - Perspective Correction

    /// Corrects keystoning using four user-defined corner points.
    /// `quad` uses normalised coordinates (0–1, origin bottom-left) matching
    /// the convention of `CIPerspectiveCorrection`.
    func applyPerspectiveCorrection(_ image: CIImage, quad: PerspectiveQuad) -> CIImage {
        let w = image.extent.width
        let h = image.extent.height

        // CIPerspectiveCorrection expects CIVector pixel coordinates
        func vec(_ p: CGPoint) -> CIVector {
            CIVector(x: p.x * w, y: p.y * h)
        }

        return image.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft":     vec(quad.topLeft),
            "inputTopRight":    vec(quad.topRight),
            "inputBottomLeft":  vec(quad.bottomLeft),
            "inputBottomRight": vec(quad.bottomRight)
        ])
    }

    // MARK: - Pixel Analysis (used by tests and histogram UI)

    /// Returns normalised luminance values (0–1) for every pixel in the image.
    /// Renders via `context` — avoid calling on large images in the main thread.
    func pixelLuminances(of image: CIImage) -> [Float] {
        // Force RGBA8 output — prevents createCGImage returning nil when the
        // CIImage contains out-of-range values from high-contrast filter steps.
        guard let cgImage = context.createCGImage(
                  image,
                  from: image.extent,
                  format: .RGBA8,
                  colorSpace: CGColorSpaceCreateDeviceRGB()
              ),
              let dataProvider = cgImage.dataProvider,
              let cfData = dataProvider.data else { return [] }

        let data      = CFDataGetBytePtr(cfData)!
        let width     = cgImage.width
        let height    = cgImage.height
        let bpr       = cgImage.bytesPerRow
        let bpp       = cgImage.bitsPerPixel / 8

        var luminances = [Float]()
        luminances.reserveCapacity(width * height)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bpr + x * bpp
                let r = Float(data[offset])     / 255.0
                let g = Float(data[offset + 1]) / 255.0
                let b = Float(data[offset + 2]) / 255.0
                luminances.append(0.299 * r + 0.587 * g + 0.114 * b)
            }
        }
        return luminances
    }
}
