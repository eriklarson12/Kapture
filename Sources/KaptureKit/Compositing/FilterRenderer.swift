import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Separate from `StripRenderer`, which stays pure CoreGraphics; the filter
/// runs at native resolution so grain gets finer on a print, not the canvas.
enum FilterRenderer {
    /// Shared (a colour drag renders continuously) and internal so
    /// `BackdropRenderer` can reuse it instead of opening a second context.
    static let context = CIContext(
        options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any]
    )

    static let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    static func apply(_ filter: PhotoFilter, to image: CGImage) -> CGImage {
        // Returned before CoreImage is touched at all, so an unfiltered strip
        // is pixel-exact and builds no context it does not need.
        guard filter != .none else { return image }

        let source = CIImage(cgImage: image)
        guard let filtered = chain(filter, source),
              let colorSpace = outputColorSpace,
              let output = context.createCGImage(
                  filtered, from: source.extent, format: .RGBA8, colorSpace: colorSpace
              )
        else {
            // A filter that fails must not lose the photograph. The strip comes
            // out unfiltered rather than not at all.
            return image
        }
        return output
    }

    private static func chain(_ filter: PhotoFilter, _ source: CIImage) -> CIImage? {
        switch filter {
        case .none:
            return source
        case .blackAndWhite:
            let mono = CIFilter.photoEffectMono()
            mono.inputImage = source
            return mono.outputImage
        case .sepia:
            let sepia = CIFilter.sepiaTone()
            sepia.inputImage = source
            sepia.intensity = 0.85
            return sepia.outputImage
        case .highContrast:
            let controls = CIFilter.colorControls()
            controls.inputImage = source
            controls.contrast = 1.4
            controls.saturation = 1.05
            return controls.outputImage
        case .grain:
            return grain(over: source)
        }
    }

    /// `CIRandomGenerator` is a function of coordinate, not time, so a frame
    /// grains identically every render — the export and preview must agree.
    private static func grain(over source: CIImage) -> CIImage? {
        guard let noise = CIFilter.randomGenerator().outputImage else { return nil }

        // The generator randomizes alpha as well as colour, which would punch
        // holes in the blend, so alpha is forced opaque before anything else.
        let opaque = noise.cropped(to: source.extent).settingAlphaOne(in: source.extent)

        // Soft light leaves mid-grey untouched, so pulling noise toward 0.5
        // is what sets grain strength; `CIColorControls` pivots contrast there.
        let temper = CIFilter.colorControls()
        temper.inputImage = opaque
        temper.saturation = 0
        temper.contrast = 0.25
        guard let tempered = temper.outputImage else { return nil }

        let blend = CIFilter.softLightBlendMode()
        blend.backgroundImage = source
        blend.inputImage = tempered
        return blend.outputImage
    }
}
