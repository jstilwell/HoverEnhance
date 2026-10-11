# Development

## Build and run

Requires Xcode (the Makefile uses `xcrun swift`).

```sh
./bin/run.sh # build it universal, as releases are, and launch it; --log also streams what it does
make run     # build, bundle, sign, and launch build/HoverEnhance.app
make log     # stream hover results from the unified log (debug builds)
make stop
make test    # unit tests
make release # a notarized DMG and a signed appcast (bin/build-release.sh)
```

Release builds keep hover details out of the log; debug builds log them for `make log`.

`Tests/Manual/preview-test.html` has an example, or where to find one, for each preview case.

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
  via `VideoPlayback` (AVPlayer). A spinner stands in for a preview that takes a moment. A small
  click-through notch sits under the cursor and joins it to the preview (`PreviewGeometry`); moving
  off the notch any way but onto the preview ends the hover at once. Clicking and switching apps end
  it too, as does scrolling anywhere else. `ScrollTap` (an active event tap) hands scroll events over
  the notch or preview to the controller and swallows the ones it uses: on the notch, a video's
  volume, shown on `VolumeRockerView` above the notch, whose space counts as the notch; on the video,
  its position.
- In Finder, `FinderItem` finds the hovered item: each one is an element with `AXFilename` and a file
  reference `AXURL`, reached from other cells of a list row or the label under an icon through the row
  or the item's group. `FileDetails` reads the card's details from Spotlight and Finder's records
  first, so protected folders aren't opened just to describe a file; `FileStatus` covers tags, iCloud,
  quarantine, and aliases, `ZipSummary` reads a zip's central directory, `AppBundleInfo` an app's
  Info.plist and signature, and `GitRepository` a repository's `.git`. Uncommitted changes come from
  `git status`, with the repository's ability to run commands switched off, or not at all when its
  config could still run one. `FileUsers` finds apps whose windows show the file (`AXDocument`) and
  processes that hold it open, map it, or work in it (`proc_listpidspath`), and quits them. The card
  grows as slower details fill in (`CardHostingView`). `MediaMetadata` reads audio and video files'
  own tags (ID3, iTunes, QuickTime) and tracks with AVFoundation, since Spotlight often hasn't. Images,
  videos, and audio show large in `FileMediaCardView`, with the card beside or below them as
  `FileMediaLayout` decides; songs play through `VideoPlayback` too. `Tests/HoverEnhanceTests/Fixtures`
  holds tiny tagged media for the tests, with the commands that made them.
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

## Releases and updates

Updates go through [Sparkle](https://sparkle-project.org). The app reads the appcast attached to the
latest GitHub release (`SUFeedURL`, through `releases/latest/download/appcast.xml`) and installs an
update only if it's signed with the key whose public half is `SUPublicEDKey`. To release:

1. Raise `CFBundleShortVersionString` in `Resources/Info.plist` and add a dated entry for it to
   `CHANGELOG.md` (its bullets become the release notes).
2. Commit, then run `./bin/build-release.sh --upload`.

The script builds a universal app signed with Developer ID and the hardened runtime, puts it in a
signed DMG, notarizes and staples it, signs the update and the appcast, and publishes both as a
GitHub release tagged at the commit it built (as a draft first, so the latest release never lacks
either file). Without `--upload` it stops before publishing and prints the command that would.

It needs, once: a Developer ID Application certificate; notary credentials saved with
`xcrun notarytool store-credentials notarytool-profile` (shared with LockAudio); the GitHub CLI,
signed in; a public repository, since release downloads from a private one need a GitHub login; and
the update signing key, in the login keychain under the account `HoverEnhance`
(`generate_keys --account HoverEnhance`, from `.build/artifacts/sparkle/Sparkle/bin`). Back that key
up (`generate_keys --account HoverEnhance -x <file>`): without it no update can ever be signed for
installed copies again.

Debug builds check only when asked, so a build from source isn't offered a release over itself.

## Icons

`design/icons/appicon.svg` and `menubar.svg` are the sources; `./bin/render-icons.sh` renders them
into `Resources/AppIcon.icns` and `Resources/MenuBarIcon.png` with headless Chrome.
