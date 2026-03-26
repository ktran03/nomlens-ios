/// The result of attempting to segment characters from an image.
enum SegmentationResult: CustomStringConvertible {
    var description: String {
        switch self {
        case .characters(let c):    return "characters(\(c.count))"
        case .zeroDetected:         return "zeroDetected"
        case .belowThreshold(let n): return "belowThreshold(\(n))"
        }
    }
    /// At least one character was found. Array is sorted into Han Nôm reading order
    /// (columns right-to-left, top-to-bottom within each column).
    case characters([CharacterCrop])

    /// Vision returned zero observations. Triggers the manual-crop fallback flow.
    case zeroDetected

    /// Vision found some observations but fewer than the minimum threshold.
    /// - Parameter count: how many were found.
    case belowThreshold(Int)
}
