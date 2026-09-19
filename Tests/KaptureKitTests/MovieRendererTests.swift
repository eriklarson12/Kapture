import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import KaptureKit

@Suite("MovieRenderer")
struct MovieRendererTests {
    /// Runs `body` against a URL in a directory that is removed afterwards.
    /// `AVAssetWriter` needs a real file, so this is the one suite that cannot
    /// work in memory.
    private func withOutputURL(_ body: (URL) async throws -> Void) async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "KaptureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory.appending(path: "movie.mp4"))
    }

    private func frames(_ count: Int) -> [CGImage] {
        (0..<count).map { TestImage.solid(width: 320, height: 240, gray: CGFloat($0) / 4) }
    }

    @Test("writing stills produces a playable movie of the expected length")
    func writesMovie() async throws {
        try await withOutputURL { url in
            try await MovieRenderer.writeMP4(frames: frames(4), secondsPerFrame: 0.8, to: url)

            #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
            let duration = try await AVURLAsset(url: url).load(.duration).seconds
            // Within a frame of 4 x 0.8. The tail is `endSession`, which is
            // what stops the last still being a zero-length frame.
            #expect(abs(duration - 3.2) < 0.1)
        }
    }

    @Test("the movie is the size of the frames it was given")
    func matchesFrameSize() async throws {
        try await withOutputURL { url in
            try await MovieRenderer.writeMP4(frames: frames(2), secondsPerFrame: 0.5, to: url)

            let track = try await #require(
                AVURLAsset(url: url).loadTracks(withMediaType: .video).first
            )
            let size = try await track.load(.naturalSize)
            #expect(size == CGSize(width: 320, height: 240))
        }
    }

    /// `NSSavePanel` hands back whatever the user picked, including a file they
    /// meant to replace, and `AVAssetWriter` refuses a URL that exists.
    @Test("writing over an existing file replaces it")
    func replacesExistingFile() async throws {
        try await withOutputURL { url in
            try Data([0x00, 0x01]).write(to: url)
            try await MovieRenderer.writeMP4(frames: frames(2), secondsPerFrame: 0.5, to: url)

            let duration = try await AVURLAsset(url: url).load(.duration).seconds
            #expect(abs(duration - 1.0) < 0.1)
        }
    }

    @Test("an odd dimension is refused rather than handed to the encoder")
    func rejectsOddDimensions() async throws {
        try await withOutputURL { url in
            await #expect(throws: MovieRenderError.oddDimensions(width: 321, height: 240)) {
                try await MovieRenderer.writeMP4(
                    frames: [TestImage.solid(width: 321, height: 240)],
                    secondsPerFrame: 0.5,
                    to: url
                )
            }
        }
    }

    @Test("a movie with no frames is refused rather than written empty")
    func rejectsEmpty() async throws {
        try await withOutputURL { url in
            await #expect(throws: MovieRenderError.noFrames) {
                try await MovieRenderer.writeMP4(frames: [], secondsPerFrame: 0.5, to: url)
            }
        }
    }

    /// 32BGRA drawn through a CGContext is one byte-order mistake away from
    /// swapping red and blue, which looks like a colour-management bug and is
    /// not one. Nothing else in the suite would catch it: the size, the
    /// duration and the file are all correct either way.
    @Test("the movie keeps red red")
    func preservesChannelOrder() async throws {
        try await withOutputURL { url in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let context = CGContext(
                data: nil, width: 320, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
            let red = context.makeImage()!

            try await MovieRenderer.writeMP4(frames: [red, red], secondsPerFrame: 0.5, to: url)

            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            let (frame, _) = try await generator.image(at: CMTime(value: 1, timescale: 10))
            let pixels = TestImage.pixels(frame)
            // Lossy, so this asks which channel dominates rather than for 255.
            #expect(pixels[0] > 180)
            #expect(pixels[2] < 80)
        }
    }
}
