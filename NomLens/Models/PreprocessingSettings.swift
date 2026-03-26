import Foundation

/// All tunable parameters for the Core Image preprocessing pipeline.
/// Each property maps directly to a filter parameter in `ImagePreprocessor`.
struct PreprocessingSettings: Equatable {

    // MARK: - Geometry

    /// Enable four-corner perspective correction (fix keystoning).
    var perspectiveCorrectionEnabled: Bool = false
    var perspectiveQuad: PerspectiveQuad = .identity

    /// Enable rotation correction.
    var deskewEnabled: Bool = false

    /// Rotation angle in radians. Range: -0.5 … 0.5.
    var straightenAngle: Float = 0.0

    // MARK: - Noise

    /// Enable `CINoiseReduction`.
    var noiseReductionEnabled: Bool = true

    /// Noise suppression strength. Range: 0.0 … 0.1. Default: 0.02.
    var noiseLevel: Float = 0.02

    /// Sharpness preserved during noise reduction. Range: 0.0 … 2.0. Default: 0.4.
    var noiseSharpness: Float = 0.4

    // MARK: - Tone

    /// `CIColorControls` contrast. Range: 0.5 … 4.0. Default: 1.3.
    /// Saturation is always forced to 0 (grayscale).
    var contrast: Float = 1.3

    /// `CIColorControls` brightness. Range: -1.0 … 1.0. Default: 0.0.
    var brightness: Float = 0.0

    // MARK: - Adaptive Threshold

    /// Enable local-contrast adaptive thresholding.
    /// Critical for stone steles with uneven illumination or shadow in carved recesses.
    var adaptiveThresholdEnabled: Bool = false

    /// Bias applied after subtracting the blurred mean. Range: -0.2 … 0.2. Default: 0.0.
    var thresholdBias: Float = 0.0

    // MARK: - Sharpening

    /// Enable `CIUnsharpMask`.
    var sharpenEnabled: Bool = true

    /// Unsharp mask radius. Range: 0.0 … 100.0. Default: 2.5.
    var sharpenRadius: Float = 2.5

    /// Unsharp mask intensity. Range: 0.0 … 1.0. Default: 0.5.
    var sharpenIntensity: Float = 0.5
}

// MARK: - Presets

extension PreprocessingSettings {

    /// Optimised for stone steles: heavy contrast, adaptive threshold, strong sharpen.
    /// Use when shooting carved inscriptions with shadow in recesses or uneven daylight.
    static var stele: PreprocessingSettings {
        var s = PreprocessingSettings()
        s.adaptiveThresholdEnabled = true
        s.contrast = 2.0
        s.noiseReductionEnabled = true
        s.sharpenIntensity = 0.8
        return s
    }

    /// Optimised for aged manuscripts: moderate contrast boost, slight brightness lift,
    /// no adaptive threshold (ink is already dark on paper).
    static var manuscript: PreprocessingSettings {
        var s = PreprocessingSettings()
        s.contrast = 1.5
        s.brightness = 0.1
        s.adaptiveThresholdEnabled = false
        s.sharpenIntensity = 0.4
        return s
    }

    /// Minimal processing for modern prints or high-quality clean photographs.
    static var cleanPrint: PreprocessingSettings {
        var s = PreprocessingSettings()
        s.noiseReductionEnabled = false
        s.sharpenEnabled = false
        return s
    }
}

// MARK: - PerspectiveQuad

/// Four corner points for `CIPerspectiveCorrection`, in normalised image coordinates (0–1).
struct PerspectiveQuad: Equatable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint

    /// Identity quad — no perspective transformation applied.
    static let identity = PerspectiveQuad(
        topLeft:     CGPoint(x: 0, y: 1),
        topRight:    CGPoint(x: 1, y: 1),
        bottomLeft:  CGPoint(x: 0, y: 0),
        bottomRight: CGPoint(x: 1, y: 0)
    )
}
