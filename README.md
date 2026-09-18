# Kapture

A macOS photobooth. Take a sequence of photos with your camera, get a classic photo strip.

Built with Swift, SwiftUI, and AVFoundation, with no third-party dependencies.

## Status

The core loop works: press a button, get four photos on a countdown, see the strip, style it, save a 300 dpi PNG. See Roadmap below.

## How it works

Kapture stores a finished strip as a *recipe*, not as a flattened image. A recipe records which frames went into the strip, which template arranged them, and which settings were applied. Nothing is baked in.

That one decision buys a lot:

- Re-editing a strip months later is lossless.
- Changing a template re-renders every strip that used it.
- A filter never degrades the original photo, because it is applied at render time.
- A recipe is small enough to send to someone as a file.

## Architecture

```
KaptureKit/          engine: models, layout math, renderer, storage
  Model/             StripTemplate, StripRecipe, StripStyle, CaptureFrame, RGBA
  Capture/           CameraSource protocol, CaptureSequence, CaptureRunner
  Compositing/       StripRenderer, RecipeRenderer, CaptionRenderer, PhotoFilter
  Storage/           StripStore, ImageCodec
  Templates/         built-in layouts

App/                 SwiftUI shell
  BoothModel.swift           app state and policy
  AVFoundationCamera.swift   the only file that touches AVFoundation
```

The engine contains no UI framework. It has no idea a camera or a window exists, which is what makes every layout decision testable without hardware. The capture driver lives there too, waiting through an injected clock, so a four shot sequence can be tested in milliseconds rather than sat through.

A strip on disk is a single package directory holding its recipe and its frames. Deleting a strip is one filesystem operation, and no frame is ever shared between two strips.

Styling a strip writes optional overrides onto its recipe rather than editing the template it uses. A value the user never touched keeps following the template, so changing a template still changes every strip that did not override it.

The live preview is letterboxed to the shape each photo is cropped to, so what you compose against is what the strip keeps.

Geometry is expressed in points, where one point is 1/72 inch, and resolution enters only at render time. The same template drives both the on-screen preview and a 300 dpi print export. The classic 2x6 inch strip renders to exactly 600x1800 pixels.

## Requirements

- macOS 14 or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), to generate the app project

Xcode is required to run the tests and to build the app. The engine alone builds with the Command Line Tools.

## Getting Started

```sh
git clone https://github.com/eriklarson/Kapture.git
cd Kapture

swift build                 # build the engine
swift test                  # run the test suite

brew install xcodegen
xcodegen generate           # produces Kapture.xcodeproj
open Kapture.xcodeproj
```

The Xcode project is generated from `project.yml` and is not committed, so build settings are edited there rather than in Xcode. Regenerating is idempotent.

## Roadmap

Working:

- Camera capture with a live mirrored preview
- Countdown, capture flash, and a review beat between shots
- Strip layout engine with aspect-fill cropping and scaled print export
- Three built-in templates
- Strips stored on disk as re-renderable recipes
- Paper, ink, border and corner styling, applied per strip and re-rendered live
- Captions set in type at output resolution, not scaled from the preview
- PNG export at 300 dpi, a true 2x6 inches

Planned:

- Filters applied at render time
- Retaking a single frame without redoing the run
- Animated GIF and MP4 export
- A gallery of past strips, re-editable
- User-authored templates as shareable files
- Fullscreen kiosk mode
- Background replacement using Vision person segmentation

## License

MIT
