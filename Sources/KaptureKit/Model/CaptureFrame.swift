import CoreGraphics
import Foundation

/// One still from a capture run. `index` is the shot's position in the strip,
/// zero-based, and survives a retake so a re-shot frame lands back in its slot.
public struct CaptureFrame: Identifiable {
    public let id: UUID
    public let index: Int
    public let capturedAt: Date
    public let image: CGImage

    public init(id: UUID = UUID(), index: Int, capturedAt: Date = Date(), image: CGImage) {
        self.id = id
        self.index = index
        self.capturedAt = capturedAt
        self.image = image
    }
}
