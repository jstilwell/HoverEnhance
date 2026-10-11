# HoverEnhance

A macOS menu-bar app that watches what the mouse rests on, in any app, and acts on it. It reads
other apps' UI through the Accessibility API, so it works in browsers without an extension.

- **Image previews** (HoverZoom-style): rest the cursor on an image or a link to one and the
  full-size image appears beside it. Site rules swap thumbnails for full-size versions on Bluesky,
  Reddit, Imgur, Wikimedia, YouTube, and Letterboxd.
- **Albums**: Reddit galleries and multi-photo posts on X, Bluesky, and Instagram show an n/total badge; scroll
  while hovering to step through them (the page underneath stays put).
- **Video**: Streamable, Reddit, X, Bluesky, Instagram, Imgur gifv, and direct .mp4/.m3u8 links play in the
  preview. Move onto the video for playback and volume controls; it resumes where you left off if it
  closes, and remembers mute/volume.
- **Embedded players**: YouTube, Vimeo, TikTok, and Twitch clip links play through each
  site's own player (skipped on the site itself, which has its own hover previews). The last one
  stays paused in the background, so hovering it again resumes.
- **Scroll wheel**: with the cursor on the notch or the preview, scrolling acts on the preview, not
  the page. Albums step through their items; images zoom (move onto the preview to pan); videos
  move through the timeline or change the volume, as set in Settings.
- **Settings** (menu bar icon → Settings…, or open the app again): when previews appear (always, or
  only/except while holding a modifier key), hover delay, excluded apps, which kinds of media and
  which sites to preview, preview size, video sound/loop/resume, cache and website data, and an
  inspector that lists what's under the cursor.

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
- `MediaResolver` turns the hovered image or link into a `MediaSource` (`ImageRules` for
  full-size image URLs, `SiteLinks` for posts and videos). `MediaFetcher` does any lookup the site
  needs (`SiteAPIs`, `RedditGallery`), giving `Media`: one item or an album.
- `PreviewController` shows items in `PreviewPanel`: images via `ImageLoader` (downsampled off the
  main thread), videos via `VideoPlayback` (AVPlayer). A small click-through notch sits under the
  cursor and joins it to the preview (`PreviewGeometry`); moving off the notch any way but onto the
  preview ends the hover at once. Clicking and switching apps end it too, as does scrolling anywhere
  else. `ScrollTap` (an active event tap) hands scroll events over the notch or preview to the
  controller and swallows the ones it uses. `ScrollTap`
  swallows scroll events while an album is up.
- `EmbedPlayer` hosts players in a web view loaded under an HTTPS origin (YouTube needs a
  Referer), with AirPlay and WebRTC off so nothing asks for local network access.
- `AppSettings` keeps settings in UserDefaults; code reads it where it's used, so changes apply at
  once. `SettingsWindowController` shows the SwiftUI tabs in `SettingsViews`.
- Reddit answers scripted requests with a JavaScript check; `WebPageLoader` passes it in an
  offscreen WebKit view and shares the cookie with URLSession.
- Chromium browsers and Electron apps only expose web content to accessibility on request, so the
  inspector sets `AXEnhancedUserInterface` (Chromium) or `AXManualAccessibility` (Electron) on them
  the first time it sees them.
