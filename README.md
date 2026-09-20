# Kapture

A macOS photobooth. Take a sequence of photos with your camera, get a classic photo strip.

Built with Swift, SwiftUI, and AVFoundation, with no third-party dependencies.

## Status

The core loop works: press a button, get four photos on a countdown, see the strip, style it, then save it as a 300 dpi PNG, a looping GIF, a movie or a PDF, paste it into another app, or print it. See Roadmap below.

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
  Model/             StripTemplate, StripRecipe, StripStyle, StripBackground, CaptureFrame, RGBA
  Capture/           CameraSource protocol, CaptureSequence, CaptureRunner
  Compositing/       StripRenderer, RecipeRenderer, ResolvedStrip, CaptionRenderer, FilterRenderer
  Export/            MovieRenderer, PDFRenderer, SheetLayout
  Storage/           StripStore, TemplateStore, ImageCodec
  Templates/         built-in layouts, and the template file format

App/                 SwiftUI shell
  BoothModel.swift           app state and policy
  StripExport.swift          export, clipboard and print policy
  TemplateExchange.swift     saving, importing and removing a template
  AVFoundationCamera.swift   the only file that touches a camera
```

The engine contains no UI framework. It has no idea a camera or a window exists, which is what makes every layout decision testable without hardware. The capture driver lives there too, waiting through an injected clock, so a four shot sequence can be tested in milliseconds rather than sat through.

A strip on disk is a single package directory holding its recipe, its frames, and any picture it uses as a background. Deleting a strip is one filesystem operation, and nothing inside one is ever shared with another.

Styling a strip writes optional overrides onto its recipe rather than editing the template it uses. A value the user never touched keeps following the template, so changing a template still changes every strip that did not override it.

A template is a small JSON file, written with its fields named so it can be edited in a text editor. Saving one takes the strip's current look rather than the layout it started from. Importing one checks it first: a file that would redefine a built-in, or that leaves no room for the photos, is refused with a message saying which. Imported templates are kept alongside the strips, because a strip goes on referring to its template rather than swallowing a copy of it.

The live preview is letterboxed to the shape each photo is cropped to, so what you compose against is what the strip keeps. The saved photo records what the lens saw, and the strip mirrors it back by default, so the result matches the person you watched on screen.

Geometry is expressed in points, where one point is 1/72 inch, and resolution enters only at render time. The same template drives the on-screen preview, a 300 dpi print export, and a PDF page. One drawing routine serves all three: it takes a graphics context rather than making one, so a bitmap, a page and a print job cannot disagree about what a strip looks like. The classic 2x6 inch strip renders to exactly 600x1800 pixels, and to a page of exactly 144x432 points.

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
- Gradient and picture backgrounds, with the picture kept inside the strip
- Filters applied at render time, never baked into the photograph
- Retaking a single shot without redoing the run
- Captions set in type at output resolution, not scaled from the preview
- PNG export at 300 dpi, a true 2x6 inches
- Animated GIF and MP4 export of the shots, cropped and filtered exactly as the strip crops them
- PDF export as a real page: the page box measures a true 2x6 inches and the caption is embedded text, not pixels
- Copy to the clipboard, as a photograph and as something a document can scale
- Printing, two strips to a 4x6 sheet, at 100% so each one is a true two inches
- Templates as shareable files: save a strip's layout as JSON, and import one back after it is checked

Planned:

- A gallery of past strips, re-editable
- A template editor, and grid layouts alongside vertical stacks
- Fullscreen kiosk mode
- Background replacement using Vision person segmentation

## License

MIT
