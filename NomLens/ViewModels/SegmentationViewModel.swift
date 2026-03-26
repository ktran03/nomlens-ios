import UIKit
import Combine

/// Drives the segmentation step of the decode pipeline.
/// Holds the result of the most recent `segment` call so the UI can react.
@MainActor
final class SegmentationViewModel: ObservableObject {

    @Published private(set) var result: SegmentationResult?
    @Published private(set) var isProcessing = false

    private let segmentor = CharacterSegmentor()

    func segment(image: UIImage) async {
        isProcessing = true
        result = await segmentor.segment(image: image)
        isProcessing = false
    }
}
