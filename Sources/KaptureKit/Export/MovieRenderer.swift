import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

public enum MovieRenderError: Error, Equatable {
    case noFrames
    /// H.264 encodes in 16x16 macroblocks and will not take an odd width or
    /// height. `RecipeRenderer.evenSize` is what normally prevents this.
    case oddDimensions(width: Int, height: Int)
    case pixelBufferUnavailable
    case writeFailed(String)
}

/// Stills out to an H.264 movie. The first engine file to import AVFoundation,
/// permitted by ADR-013: this is the framework's *writing* half, which has no
/// UI, no hardware and no global state. Capture types stay out of the engine —
/// `CameraSource` is still the only door to a camera.
public enum MovieRenderer {
    private static let timescale: CMTimeScale = 600

    /// Writes `frames` to `url` as an MP4, holding each for `secondsPerFrame`.
    ///
    /// A URL rather than `Data` because `AVAssetWriter` only writes to a file.
    /// Every frame is drawn at the first frame's size, which is what
    /// `RecipeRenderer.renderFrames` already guarantees.
    public static func writeMP4(
        frames: [CGImage], secondsPerFrame: Double, to url: URL
    ) async throws {
        guard let first = frames.first else { throw MovieRenderError.noFrames }
        let width = first.width
        let height = first.height
        guard width % 2 == 0, height % 2 == 0 else {
            throw MovieRenderError.oddDimensions(width: width, height: height)
        }

        // `AVAssetWriter` refuses a URL that already exists, and `NSSavePanel`
        // hands back whatever the user picked, including a file they meant to
        // overwrite.
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        writer.add(input)

        guard writer.startWriting() else {
            throw MovieRenderError.writeFailed(message(for: writer))
        }
        writer.startSession(atSourceTime: .zero)

        for (index, frame) in frames.enumerated() {
            // Appending while the input is not ready is dropped rather than
            // reported, which produces a short movie and no error anywhere.
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            let buffer = try pixelBuffer(for: frame, from: adaptor, width: width, height: height)
            guard adaptor.append(buffer, withPresentationTime: time(Double(index) * secondsPerFrame))
            else { throw MovieRenderError.writeFailed(message(for: writer)) }
        }

        input.markAsFinished()
        // Ends past the last frame, so the final still has a duration instead
        // of being a zero-length tail the player skips.
        writer.endSession(atSourceTime: time(Double(frames.count) * secondsPerFrame))
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw MovieRenderError.writeFailed(message(for: writer))
        }
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(value: Int64((seconds * Double(timescale)).rounded()), timescale: timescale)
    }

    private static func message(for writer: AVAssetWriter) -> String {
        writer.error?.localizedDescription ?? "status \(writer.status.rawValue)"
    }

    /// One frame drawn into a buffer from the adaptor's own pool.
    ///
    /// `noneSkipFirst` with `byteOrder32Little` is what 32BGRA means to
    /// CoreGraphics. Getting it wrong swaps red and blue, which reads as a
    /// colour-management bug and is not one.
    private static func pixelBuffer(
        for image: CGImage,
        from adaptor: AVAssetWriterInputPixelBufferAdaptor,
        width: Int,
        height: Int
    ) throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else {
            throw MovieRenderError.pixelBufferUnavailable
        }
        var created: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created) == kCVReturnSuccess,
              let buffer = created else {
            throw MovieRenderError.pixelBufferUnavailable
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: base,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { throw MovieRenderError.pixelBufferUnavailable }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
