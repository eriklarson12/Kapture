# Kapture

A macOS photobooth. Take a sequence of photos with your camera, get a classic photo strip.

Built with Swift, SwiftUI, and AVFoundation, with no third-party dependencies.

## Status

The core loop works: press a button, get four photos on a countdown, see the strip, style it, then save it as a 300 dpi PNG, a looping GIF, a movie or a PDF, paste it into another app, or print it. It also runs a party: fullscreen with no chrome, a queue that restarts itself, a backdrop painted in behind the subject, and a QR code a guest scans to take their strip home on their own phone. See Roadmap below.

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
  Capture/           CameraSource protocol, CaptureSequence, CaptureCue, CaptureRunner, RestartTimer
  Audio/             SoundCue: the countdown, shutter and finish sounds, as arithmetic
  Compositing/       StripRenderer, RecipeRenderer, ResolvedStrip, CaptionRenderer, FilterRenderer, BackdropRenderer, PersonMaskStore
  Export/            MovieRenderer, PDFRenderer, SheetLayout
  Serve/             HTTP as values, the share token and page, the QR code, the listener
  Storage/           StripStore, TemplateStore, ImageCodec
  Templates/         built-in layouts, and the template file format

App/                 SwiftUI shell
  BoothModel.swift           app state and policy
  StripExport.swift          export, clipboard and print policy
  TemplateExchange.swift     saving, importing, editing and removing a template
  TemplateEditorView.swift   the template editor sheet
  BoothSounds.swift          the cue sink: plays what the engine generated
  KioskMode.swift            fullscreen plumbing for kiosk mode
  StripSharing.swift         the share link: one strip at a time, over the LAN
  AVFoundationCamera.swift   the only file that touches a camera
```

The engine contains no UI framework. It has no idea a camera or a window exists, which is what makes every layout decision testable without hardware. The capture driver lives there too, waiting through an injected clock, so a four shot sequence can be tested in milliseconds rather than sat through.

A strip on disk is a single package directory holding its recipe, its frames, and any picture it uses as a background. Deleting a strip is one filesystem operation, and nothing inside one is ever shared with another.

Styling a strip writes optional overrides onto its recipe rather than editing the template it uses. A value the user never touched keeps following the template, so changing a template still changes every strip that did not override it.

A template is a small JSON file, written with its fields named so it can be edited in a text editor, and carrying its own extension so double-clicking it opens Kapture rather than a code editor. Saving one takes the strip's current look rather than the layout it started from. Importing one checks it first: a file that would redefine a built-in, or that leaves no room for the photos, is refused with a message saying which. Imported templates are kept alongside the strips, because a strip goes on referring to its template rather than swallowing a copy of it.

That reference is also why editing a template moves the strips that use it. The editor changes the shot count, the number of columns, the paper and the chrome, with a wireframe of the layout that keeps up as you drag. One control is held still: the number of shots, once a strip already uses the template. Every other change makes a past strip look different, which is the point of keeping the reference; that one would stop it rendering at all.

Photos can be stacked down a strip or arranged in a grid. The two are the same layout with a different number of columns, so a grid inherits every rule a strip already had rather than being a second thing to maintain.

Kapture makes three sounds and no others: a tick on each second of the countdown, a snap with the flash rather than after it, and a chime when the strip appears. None of them is a file. The waveforms are arithmetic in the engine, seeded so the same cue is the same bytes on every machine, which means they cost nothing to ship and can be tested rather than merely listened to. The run driver announces the moment; what it sounds like, and whether anything is heard at all, is decided elsewhere.

Kiosk mode takes the window fullscreen and takes everything out of it: no inspector, no buttons, no title bar. What is left is the picture, the countdown, and one dim line naming the two keys. Space shoots and Escape stops whatever is currently happening. It is fullscreen rather than a locked-down presentation mode on purpose, because the setting that stops a guest wandering off is the same setting that strands whoever is running the party.

A booth left to run a party restarts itself. When a strip is finished it is held for a set number of seconds with the count on screen, and then the next run begins; a key press goes early or stops the queue. It only happens in kiosk mode, where there is nothing to interrupt — anywhere else the timer would be throwing away the strip somebody is editing. A camera failure ends the queue rather than restarting into it, because a booth that retries a broken camera never gives anyone a gap to fix it in.

The strip on screen can be handed to a phone. Kapture serves it over the local network and shows a QR code next to the picture; scanning it opens a page with the 300 dpi strip and the looping GIF. One strip is shared at a time, behind an unguessable code, so a link photographed two minutes ago stops working rather than quietly showing whoever is in front of the camera now. Nothing is written down: every link dies when the app quits. The server is a few hundred lines in the engine — request parsing, routing and the page are ordinary values with ordinary tests, and only the socket is left over.

The background behind a person can be replaced. Vision finds the subject in each stored photograph and everything behind them is painted over with a colour, a gradient or a picture — the same three choices the paper already offered, painted by the same code, so a gradient behind a person and a gradient behind the photos read the same angle. Nothing is baked: the mask is taken at render time from the photograph as the camera recorded it, which is why the backdrop can be changed or dropped a year later, why it turns with the subject when the strip is mirrored, and why the filter lands on the finished composite rather than on the person alone. A photograph with nobody in it is left alone rather than replaced entirely, because a model that finds nothing says so by returning an empty mask, and painting that would hand somebody four rectangles of colour instead of their strip.

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
- Four built-in templates, three strips and a grid
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
- Templates as shareable files: save a strip's layout, and import one back after it is checked, or by double-clicking it in Finder
- A template editor: shot count, columns, paper and chrome, with a live wireframe of the layout
- Grid layouts alongside vertical stacks, including a 2x2 on a 4x6 print
- Fullscreen kiosk mode: keyboard only, no chrome, one key in and one key out
- Countdown, shutter and finish sounds, synthesized rather than shipped
- Auto-restart between runs, so a queue keeps moving without anyone at the keyboard
- A captured strip served to a phone on the same Wi-Fi, by QR code, one strip at a time
- Background replacement: Vision finds the person, and a colour, gradient or picture goes behind them

Planned:

- A gallery of past strips, re-editable
- Face detection to centre the crop on the subject

## License

MIT
