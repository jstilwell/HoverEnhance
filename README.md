# HoverEnhance

A macOS menu-bar app that watches what the mouse rests on, in any app, and acts on it. It reads
other apps' UI through the Accessibility API, so it works in browsers without an extension.

- **Image previews** (HoverZoom-style): rest the cursor on an image or a link to one and the
  full-size image appears beside it. Site rules swap thumbnails for full-size versions on Bluesky,
  Reddit, Imgur, Wikimedia, YouTube, and Letterboxd. An image over the download limit (25 MB unless
  set otherwise) shows its size instead, with Load Anyway.
- **Browsers first**: previews that load from the network appear in browsers, where loading a link
  does no more than the page could. Settings → General can allow other apps; turning that on offers
  to skip email apps (a link loaded from an email can tell its sender you read it), to stick to known
  sites, and to wait for a key. Links from web pages never lead to local files.
- **Albums**: Reddit galleries and multi-photo posts on X, Bluesky, and Instagram show an n/total badge; scroll
  while hovering to step through them (the page underneath stays put).
- **Video**: Streamable, Reddit, X, Bluesky, Instagram, Imgur gifv, and direct .mp4/.m3u8 links play in the
  preview. Move onto the video for playback and volume controls; it resumes where you left off if it
  closes, and remembers mute/volume.
- **Embedded players**: YouTube, Vimeo, TikTok, and Twitch clip links play through each
  site's own player (skipped on the site itself, which has its own hover previews). The last one
  stays paused in the background, so hovering it again resumes.
- **Creator cards** (YouTube): on youtube.com, hovering a video title or channel name shows the
  creator's avatar, counts, and description, with Subscribe/Unsubscribe once you sign in under
  Settings → Accounts (your own Google Cloud OAuth client). Thumbnails and YouTube's own hover
  previews are left alone.
- **File cards** (Finder): resting on a file or folder in any Finder view or on the desktop shows a
  card with a thumbnail and its path (click to copy it in full, with ~, or quoted for the shell), and
  whichever of these it has: kind, size, dates, where an alias points, the website and app a download
  came from, tags, iCloud status, dimensions, length, pages, camera, lens, exposure, codecs, artist and
  album, a zip's contents, an app's version, bundle ID, architectures, minimum macOS, and signature, and
  a repository's branch, remote, and uncommitted changes. Click any detail to copy it. It also lists
  the apps using the file (open in a window, held open, or working in the folder), each with Quit and,
  if that doesn't work, Force Quit. A key press (Space for Quick Look, Return to rename) closes the
  card. Settings → Finder has a switch for every detail, and for cards on the desktop and for folders.
- **Scroll wheel**: with the cursor on the notch or the preview, scrolling acts on the preview, not
  the page. Albums step through their items; images zoom (move onto the preview to pan); videos
  move through the timeline or change the volume, as set in Settings.
- **Updates**: release builds check for updates with Sparkle and install them on request. A version
  found in the background is offered in the menu bar menu (with a dot on the icon) rather than in a
  window that would open behind others.
- **Settings** (menu bar icon → Settings…, or open the app again): when previews appear (always, or
  only/except while holding a modifier key), hover delay, other apps, excluded apps, which kinds of
  media and which sites to preview, what file cards show, preview size and download limit, video
  sound/loop/resume, cache and website data, and an inspector that lists what's under the cursor.

## Build and run

Requires Xcode (the Makefile uses `xcrun swift`).

```sh
make run     # build, bundle, sign, and launch build/HoverEnhance.app
make log     # stream hover results from the unified log (debug builds)
make stop
make test    # unit tests
make release # a notarized DMG and a signed appcast (bin/build-release.sh)
```

Release builds keep hover details out of the log; debug builds log them for `make log`.

### Releases and updates

Updates go through [Sparkle](https://sparkle-project.org): the app reads the appcast at `SUFeedURL`
and installs a release only if its signature matches `SUPublicEDKey`. Both the appcast and the DMGs
live in a Cloudflare R2 bucket behind a custom domain. To release:

1. Raise `CFBundleShortVersionString` in `Resources/Info.plist` and add a dated entry for it to
   `CHANGELOG.md` (its bullets become the release notes).
2. Commit, then run `op run --env-file=.env -- ./bin/build-release.sh --upload` (or with a plain
   `.env` made from `.env.example`, just `./bin/build-release.sh --upload`).

The script builds a universal app signed with Developer ID and the hardened runtime, puts it in a
signed DMG, notarizes and staples it, signs the update and the appcast, then uploads the DMG to
`releases/` in the bucket, creates a GitHub release for the record, and publishes the appcast last.
Without `--upload` it stops before publishing; `./bin/copy-appcast.sh` publishes the appcast later.

It needs, once: a Developer ID Application certificate; notary credentials saved with
`xcrun notarytool store-credentials notarytool-profile` (shared with LockAudio); the AWS CLI with an
`r2` profile; and the update signing key, which lives in the login keychain under the account
`HoverEnhance` (`generate_keys --account HoverEnhance`, from `.build/artifacts/sparkle/Sparkle/bin`).
Back that key up (`generate_keys --account HoverEnhance -x <file>`): without it no update can ever
be signed for installed copies again.

Debug builds never check on their own, so a build from source isn't offered a release over itself;
Check for Updates still works for testing. A build without a feed URL (before the first release)
has no updater at all.

### Icons

`design/icons/appicon.svg` and `menubar.svg` are the sources; `./bin/render-icons.sh` renders them
into `Resources/AppIcon.icns` and `Resources/MenuBarIcon.png` with headless Chrome.

`Tests/Manual/preview-test.html` has one example of each preview case to hover in any browser.

Nothing runs without Accessibility access. On first launch a welcome window opens the Accessibility
settings and offers the app's icon to drag into the list; the app starts once access is on, and the
window comes back if access is turned off. The bundle is signed with your first Apple Development /
Developer ID identity so the grant survives rebuilds. With ad-hoc signing you'd have to re-grant
after every build (the welcome window explains how to remove and re-add the app).

## How it works

- `AccessibilityWatcher` follows whether the app has Accessibility access; `WelcomeWindowController`
  shows the guide until it does, and `AppDelegate` starts everything else once it has.
- `HoverMonitor` listens for global mouse-moved events and waits for the cursor to rest (150 ms).
- `HoverInspector` hit-tests with `AXUIElementCopyElementAtPosition` on a background queue (AX
  calls are synchronous IPC into the target app) and walks up to the enclosing link and web area.
- `MediaResolver` turns the hovered image or link into a `MediaSource` (`ImageRules` for
  full-size image URLs, `SiteLinks` for posts and videos), following `file:` URLs only from local
  pages. `MediaFetcher` does any lookup the site needs (`SiteAPIs`, `RedditGallery`), giving `Media`:
  one item or an album, with web addresses only. `AppKind` tells browsers and email apps apart from
  what they declare they open, and `OtherAppsPolicy` decides what may load outside browsers.
- `PreviewController` shows items in `PreviewPanel`: images via `ImageLoader` (downloaded through
  `LimitedDownloader`, which stops at the size limit, and downsampled off the main thread), videos
  via `VideoPlayback` (AVPlayer). A spinner stands in for a preview that takes a moment. A small click-through notch sits under the
  cursor and joins it to the preview (`PreviewGeometry`); moving off the notch any way but onto the
  preview ends the hover at once. Clicking and switching apps end it too, as does scrolling anywhere
  else. `ScrollTap` (an active event tap) hands scroll events over the notch or preview to the
  controller and swallows the ones it uses.
- In Finder, `FinderItem` finds the hovered item: each one is an element with `AXFilename` and a file
  reference `AXURL`, reached from other cells of a list row or the label under an icon through the row
  or the item's group. `FileDetails` reads the card's details from Spotlight and Finder's records
  first, so protected folders aren't opened just to describe a file; `FileStatus` covers tags, iCloud,
  quarantine, and aliases, `ZipSummary` reads a zip's central directory, `AppBundleInfo` an app's
  Info.plist and signature, and `GitRepository` a repository's `.git`. Uncommitted changes come from
  `git status`, with the repository's ability to run commands switched off, or not at all when its
  config could still run one. `FileUsers` finds apps whose windows show the file (`AXDocument`) and
  processes that hold it open, map it, or work in it (`proc_listpidspath`), and quits them. The card
  grows as slower details fill in (`CardHostingView`).
- `EmbedPlayer` hosts players in a web view loaded under an HTTPS origin (YouTube needs a
  Referer), with AirPlay and WebRTC off so nothing asks for local network access. Links clicked in a
  player open in the browser.
- `Updates` wraps Sparkle's updater; the Makefile bundles `Sparkle.framework` into the app (without
  the XPC services, which only sandboxed apps use) and signs it from the inside out.
- `AppSettings` keeps settings in UserDefaults; code reads it where it's used, so changes apply at
  once. `SettingsWindowController` shows the SwiftUI tabs in `SettingsViews`.
- Reddit answers scripted requests with a JavaScript check; `WebPageLoader` passes it in an
  offscreen WebKit view and shares the cookie with URLSession.
- Chromium browsers and Electron apps only expose web content to accessibility on request, so the
  inspector sets `AXEnhancedUserInterface` (Chromium) or `AXManualAccessibility` (Electron) on them
  the first time it sees them. Chrome ignores `AXManualAccessibility`, so it gets the VoiceOver switch,
  which makes AppKit animate window moves made through accessibility; window managers such as
  Rectangle work around that.
