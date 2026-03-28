/// The result of attempting to segment characters from an image.
enum SegmentationResult: CustomStringConvertible {
    var description: String {
        switch self {
        case .characters(let c):        return "characters(\(c.count))"
        case .twoOptions(let a, let b): return "twoOptions(\(a.count), \(b.count))"
        case .zeroDetected:             return "zeroDetected"
        case .belowThreshold(let n):    return "belowThreshold(\(n))"
        }
    }
    /// At least one character was found. Array is sorted into Han Nôm reading order
    /// (columns right-to-left, top-to-bottom within each column).
    case characters([CharacterCrop])

    /// Two projection strategies produced different crop counts — let the user pick.
    /// Both arrays are already sorted into reading order.
    /// - optionA: standard column-first path
    /// - optionB: row-first path with valley splitting
    case twoOptions([CharacterCrop], [CharacterCrop])

    /// Vision returned zero observations. Triggers the manual-crop fallback flow.
    case zeroDetected

    /// Fewer than the minimum threshold of characters detected.
    case belowThreshold(Int)
}
