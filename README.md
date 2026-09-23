# Kapture

Take a sequence of photos with your camera and get a classic photo strip on macOS.

Built with Swift, SwiftUI, and AVFoundation, with no third-party dependencies.

## Features

- **Capture:** live mirrored preview, countdown, flash, and sounds. Each photo is cropped to centre on the faces in it. Retake a single shot without redoing the run.
- **Templates:** vertical strips and grid layouts. Build your own in the template editor, then save and share it as a file.
- **Styling:** paper, ink, border, and corner styles. Add solid, gradient, or picture backgrounds, filters, and captions.
- **Background replacement:** finds the person in each photo and puts a colour, gradient, or picture behind them.
- **Lossless editing:** strips are stored as recipes, not flattened images, so you can re-edit them at any time.
- **Export:** 300 dpi PNG, animated GIF, MP4, and PDF. You can also copy to the clipboard or print two strips to a 4x6 sheet.
- **Kiosk mode:** fullscreen with keyboard-only controls. It restarts between runs automatically, so a party can run itself.
- **Share to phone:** scan a QR code to get the strip on a phone on the same Wi-Fi.

## How It Works

Kapture is split into two parts:

- **`KaptureKit`** (`Sources/`): the engine. It holds the models, layout math, rendering, export, and storage. It has no UI and never touches a camera, so every layout decision is testable without hardware.
- **App** (`App/`): a thin SwiftUI shell over the engine. `AVFoundationCamera.swift` is the only file that talks to the camera.

A finished strip is saved as a *recipe*: which photos, which template, and which settings. Nothing is baked in. Filters, backdrops, and captions are applied at render time, so edits are lossless and changing a template updates every strip that uses it.

Layouts are measured in points (1/72 inch). Resolution is only chosen at render time, so the same template drives the on-screen preview, a 300 dpi print, and a PDF page.

## Installation & Setup

### Download

Download the latest `Kapture-<version>.dmg` from [Releases](https://github.com/eriklarson12/Kapture/releases/latest). Open it and drag Kapture into Applications. Requires macOS 14 or later, on Apple silicon or Intel.

Kapture is free and not notarized by Apple, so macOS blocks it the first time:

1. Open Kapture and click **Done** on the warning.
2. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Kapture.
3. Open Kapture again and confirm.

This is only needed once per version. Each new version also asks for camera access again.

### Build from Source

Requirements:

- macOS 14 or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```sh
git clone https://github.com/eriklarson12/Kapture.git
cd Kapture

brew install xcodegen
xcodegen generate           # produces Kapture.xcodeproj
open Kapture.xcodeproj
```

Build and run the `Kapture` scheme in Xcode. To run the tests:

```sh
swift test
```

The Xcode project is generated from `project.yml` and is not committed. Edit build settings in `project.yml`, not in Xcode.

## License

MIT
