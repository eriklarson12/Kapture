import CoreGraphics
import Foundation
import Testing
@testable import KaptureKit

@Suite("FaceFramer")
struct FaceFramerTests {
    private let frame = CGSize(width: 1920, height: 1080)
    private let classicAspect = BuiltInTemplates.classicStrip.photoAspect
    private let centre = CGPoint(x: 0.5, y: 0.5)

    // MARK: - Geometry

    /// A frame whose faces are centred must crop exactly as a frame with none
    /// does, or turning the feature on moves every well-composed photo.
    @Test("a centred focus crops the region the centred aspect-fill shows")
    func centredMatchesAspectFill() {
        let crop = FaceFramer.cropRect(imageSize: frame, aspect: classicAspect, focus: centre)

        let photo = BuiltInTemplates.classicStrip.photoRects()[0]
        let drawn = StripRenderer.aspectFillRect(
            for: TestImage.solid(width: Int(frame.width), height: Int(frame.height)),
            in: photo
        )
        let shownFraction = photo.width / drawn.width
        let shownWidth = frame.width * shownFraction
        let shownX = (photo.minX - drawn.minX) / drawn.width * frame.width

        #expect(abs(crop.width - shownWidth) <= 1)
        #expect(abs(crop.minX - shownX) <= 1)
        #expect(crop.height == frame.height)
    }

    @Test("a focus near the right edge slides the crop right and stops at the edge")
    func clampsRight() {
        let crop = FaceFramer.cropRect(
            imageSize: frame, aspect: classicAspect, focus: CGPoint(x: 0.9, y: 0.5)
        )
        let centred = FaceFramer.cropRect(imageSize: frame, aspect: classicAspect, focus: centre)
        #expect(crop.minX > centred.minX)
        #expect(crop.maxX == frame.width)
    }

    @Test("a focus at the left edge stops the crop at the left edge")
    func clampsLeft() {
        let crop = FaceFramer.cropRect(
            imageSize: frame, aspect: classicAspect, focus: CGPoint(x: 0, y: 0.5)
        )
        #expect(crop.minX == 0)
    }

    @Test("a portrait photo rect slides across a landscape frame")
    func portrait() {
        let aspect: CGFloat = 0.75
        let focus = CGPoint(x: 0.25, y: 0.5)
        let crop = FaceFramer.cropRect(imageSize: frame, aspect: aspect, focus: focus)
        let expectedWidth: CGFloat = 810
        let expectedX: CGFloat = 75
        #expect(crop.width == expectedWidth)
        #expect(crop.minX == expectedX)
        #expect(crop.height == frame.height)
    }

    @Test("a photo rect wider than the frame crops vertically instead")
    func wideCropsVertically() {
        let aspect: CGFloat = 3
        let top = FaceFramer.cropRect(
            imageSize: frame, aspect: aspect, focus: CGPoint(x: 0.5, y: 1)
        )
        let expectedHeight: CGFloat = 640
        #expect(top.width == frame.width)
        #expect(top.height == expectedHeight)
        #expect(top.maxY == frame.height)
    }

    @Test("every crop is whole pixels, keeps its aspect, and stays inside the frame")
    func alwaysInside() {
        let bounds = CGRect(origin: .zero, size: frame)
        for aspect in [0.5, 0.75, 1, classicAspect, 2, 4] as [CGFloat] {
            for x in stride(from: -0.2, through: 1.2, by: 0.1) {
                for y in stride(from: -0.2, through: 1.2, by: 0.1) {
                    let crop = FaceFramer.cropRect(
                        imageSize: frame, aspect: aspect, focus: CGPoint(x: x, y: y)
                    )
                    #expect(bounds.contains(crop))
                    #expect(crop.minX == crop.minX.rounded())
                    #expect(crop.minY == crop.minY.rounded())
                    #expect(crop.width == crop.width.rounded())
                    #expect(crop.height == crop.height.rounded())
                    #expect(abs(crop.width / crop.height - aspect) < 0.01)
                }
            }
        }
    }

    // MARK: - Faces

    @Test("no faces is no focus")
    func noFaces() {
        #expect(FaceFramer.focus(of: []) == nil)
    }

    @Test("two people at opposite edges are framed between them")
    func unionOfFaces() {
        let left = CGRect(x: 0.05, y: 0.4, width: 0.1, height: 0.2)
        let right = CGRect(x: 0.75, y: 0.4, width: 0.1, height: 0.2)
        let focus = FaceFramer.focus(of: [left, right])
        let expectedX: CGFloat = 0.45
        let expectedY: CGFloat = 0.5
        #expect(abs((focus?.x ?? 0) - expectedX) < 0.0001)
        #expect(abs((focus?.y ?? 0) - expectedY) < 0.0001)
    }

    /// A poster on the wall must not pull the crop off the person in front of
    /// the camera.
    @Test("a small face far back is ignored")
    func smallFaceIgnored() {
        let subject = CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.4)
        let poster = CGRect(x: 0.9, y: 0.8, width: 0.03, height: 0.05)
        let focus = FaceFramer.focus(of: [subject, poster])
        #expect(focus == CGPoint(x: subject.midX, y: subject.midY))
    }

    // MARK: - Cropping

    @Test("cropping toward the left keeps the stripe a centred crop loses")
    func croppedKeepsTheLeftEdge() {
        let image = TestImage.edgeMarked()
        let aspect: CGFloat = 1
        let left = FaceFramer.cropped(image, aspect: aspect, focus: CGPoint(x: 0, y: 0.5))
        let centred = FaceFramer.cropped(image, aspect: aspect, focus: centre)

        #expect(left.width == image.height)
        #expect(TestImage.red(left, x: 2, y: left.height / 2) > 223)
        #expect(TestImage.red(centred, x: 2, y: centred.height / 2) < 32)
    }

    /// `CGImage.cropping(to:)` counts rows from the top and the crop rect is
    /// bottom-left. Getting that wrong frames the feet instead of the face.
    @Test("a focus near the top keeps the top of the frame")
    func croppedKeepsTheTop() {
        let image = topRed(width: 640, height: 480)
        let cropped = FaceFramer.cropped(image, aspect: 3, focus: CGPoint(x: 0.5, y: 0.9))
        #expect(TestImage.red(cropped, x: 10, y: 0) > 223)
        #expect(TestImage.red(cropped, x: 10, y: cropped.height - 1) > 223)
    }

    @Test("a photo that already fits is returned untouched")
    func alreadyFits() {
        let image = TestImage.solid(width: 400, height: 400)
        #expect(FaceFramer.cropped(image, aspect: 1, focus: CGPoint(x: 0, y: 0)) === image)
    }

    // MARK: - Vision

    /// The one test that runs Vision. It claims only that a frame with nobody
    /// in it gets no focus, so the caller crops about the centre as before.
    @Test("a flat patch has no faces")
    func visionFindsNobody() {
        #expect(FaceFramer.focus(for: TestImage.solid(width: 320, height: 240)) == nil)
    }

    private func topRed(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        return context.makeImage()!
    }
}
