# HoverEnhance

A macOS menu-bar app that watches what the mouse rests on, in any app, and acts on it. It reads
other apps' UI through the Accessibility API, so it works in browsers without an extension.

Right now it's an inspector: when the cursor settles, a HUD in the bottom-right corner shows the
element's role, labels, and URLs (link href, image src, page URL).

## Build and run

Requires Xcode (the Makefile uses `xcrun swift`).

```sh
make run     # build, bundle, sign, and launch build/HoverEnhance.app
make log     # stream hover results from the unified log
make stop
```

On first launch, grant Accessibility access in System Settings → Privacy & Security →
Accessibility. The bundle is signed with your first Apple Development / Developer ID identity so
the grant survives rebuilds. With ad-hoc signing you'd have to re-grant after every build.

## How it works

- `HoverMonitor` listens for global mouse-moved events and waits for the cursor to rest (150 ms).
- `HoverInspector` hit-tests with `AXUIElementCopyElementAtPosition` on a background queue (AX
  calls are synchronous IPC into the target app) and walks up to the enclosing link and web area.
- Chromium browsers and Electron apps only expose web content to accessibility on request, so the
  inspector sets `AXEnhancedUserInterface` (Chromium) or `AXManualAccessibility` (Electron) on them
  the first time it sees them.
