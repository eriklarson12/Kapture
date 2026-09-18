# Kapture

A macOS photobooth. Take a sequence of photos with your camera, get a classic photo strip.

Built with Swift, SwiftUI, and AVFoundation, with no third-party dependencies.

## Status

Early. The compositing engine is built and verified; the camera and UI layers are in progress. See Roadmap below for what works and what does not.

## How it works

Kapture stores a finished strip as a *recipe*, not as a flattened image. A recipe records which frames went into the strip, which template arranged them, and which settings were applied. Nothing is baked in.

That one decision buys a lot:

- Re-editing a strip months later is lossless.
- Changing a template re-renders every strip that used it.
- A filter never degrades the original photo, because it is applied at render time.
- A recipe is small enough to send to someone as a file.

## Architecture

```
KaptureKit/          engine: models, layout math, renderer
  Model/             StripTemplate, StripRecipe, CaptureFrame, CaptureSequence
  Compositing/       StripRenderer, PhotoFilter
  Capture/           CameraSource protocol
  Templates/         built-in layouts

App/                 SwiftUI shell
  AVFoundationCamera.swift   the only file that touches AVFoundation
```

The engine imports only Foundation, CoreGraphics, and CoreImage. It has no idea a camera or a window exists, which is what makes every layout decision testable without hardware.

Geometry is expressed in points, where one point is 1/72 inch, and resolution enters only at render time. The same template drives both the on-screen preview and a 300 dpi print export. The classic 2x6 inch strip renders to exactly 600x1800 pixels.

## Requirements

- macOS 14 or later
- Xcode 16 or later

Xcode is required to run the tests and to build the app. The engine alone builds with the Command Line Tools.

## Getting Started

```sh
git clone https://github.com/eriklarson/Kapture.git
cd Kapture
swift build     # builds the engine
swift test      # runs the test suite (requires Xcode)
```

## Roadmap

Working:

- Strip layout engine with aspect-fill cropping and scaled print export
- Three built-in templates
- Recipe and template serialization

In progress:

- Camera capture and live preview
- Countdown and capture sequence
- PNG export

Planned:

- Border, background, caption, and filter customization
- Animated GIF and MP4 export
- A gallery of past strips, re-editable
- User-authored templates as shareable files
- Fullscreen kiosk mode
- Background replacement using Vision person segmentation

## License

MIT
