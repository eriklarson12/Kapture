import Foundation

/// The timing plan for one photobooth run: how many shots, how long the
/// countdown runs before each, and how long the captured frame is held on
/// screen before the next countdown starts.
public struct CaptureSequence: Codable, Equatable, Sendable {
    public var frameCount: Int
    public var countdownSeconds: Int
    public var reviewSeconds: Double

    public init(frameCount: Int = 4, countdownSeconds: Int = 3, reviewSeconds: Double = 1.0) {
        self.frameCount = frameCount
        self.countdownSeconds = countdownSeconds
        self.reviewSeconds = reviewSeconds
    }

    public static let standard = CaptureSequence()

    /// Wall-clock length of a full run, for the progress indicator.
    public var totalDuration: Double {
        let perFrame = Double(countdownSeconds) + reviewSeconds
        return perFrame * Double(frameCount) - reviewSeconds
    }
}
