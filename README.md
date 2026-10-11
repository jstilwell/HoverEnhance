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
- `MediaResolver` turns the hovered image or link into a `MediaSource` (`ImageRules` for
  full-size image URLs, `SiteLinks` for posts and videos). `MediaFetcher` does any lookup the site
  needs (`SiteAPIs`, `RedditGallery`), giving `Media`: one item or an album.
- `PreviewController` shows items in `PreviewPanel`: images via `ImageLoader` (downsampled off the
  main thread), videos via `VideoPlayback` (AVPlayer). It hides the preview when the cursor leaves
  the element (or the video, for videos), on scroll or click, or on app switch. `ScrollTap`
  swallows scroll events while an album is up.
- `EmbedPlayer` hosts players in a web view loaded under an HTTPS origin (YouTube needs a
  Referer), with AirPlay and WebRTC off so nothing asks for local network access.
- Reddit answers scripted requests with a JavaScript check; `WebPageLoader` passes it in an
  offscreen WebKit view and shares the cookie with URLSession.
- Chromium browsers and Electron apps only expose web content to accessibility on request, so the
  inspector sets `AXEnhancedUserInterface` (Chromium) or `AXManualAccessibility` (Electron) on them
  the first time it sees them.
