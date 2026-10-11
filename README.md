# HoverEnhance

A macOS menu-bar app that watches what the mouse rests on, in any app, and acts on it. It reads
other apps' UI through the Accessibility API, so it works in browsers without an extension.

- **Image previews** (HoverZoom-style): rest the cursor on an image or a link to one and the
  full-size image appears beside it. Site rules swap thumbnails for full-size versions on Bluesky,
  Reddit, Imgur, Wikimedia, YouTube, and Letterboxd.
- **Inspector** (menu → Show Inspector): a HUD showing the hovered element's role, labels, and URLs.

## Build and run

Requires Xcode (the Makefile uses `xcrun swift`).

```sh
make run     # build, bundle, sign, and launch build/HoverEnhance.app
make log     # stream hover results from the unified log
make stop
make test    # unit tests
```

`Tests/Manual/preview-test.html` has one example of each preview case to hover in any browser.

On first launch, grant Accessibility access in System Settings → Privacy & Security →
Accessibility. The bundle is signed with your first Apple Development / Developer ID identity so
the grant survives rebuilds. With ad-hoc signing you'd have to re-grant after every build.

## How it works

- `HoverMonitor` listens for global mouse-moved events and waits for the cursor to rest (150 ms).
- `HoverInspector` hit-tests with `AXUIElementCopyElementAtPosition` on a background queue (AX
  calls are synchronous IPC into the target app) and walks up to the enclosing link and web area.
- `ImageResolver`/`ImageRules` turn the hovered image or link into full-size candidate URLs;
  `ImageLoader` fetches the first that works and downsamples it to screen size off the main thread;
  `ImagePreviewController` shows it in `PreviewPanel` and hides it when the cursor leaves the
  element, on scroll or click, or on app switch.
- Chromium browsers and Electron apps only expose web content to accessibility on request, so the
  inspector sets `AXEnhancedUserInterface` (Chromium) or `AXManualAccessibility` (Electron) on them
  the first time it sees them.
