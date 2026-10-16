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
settings, adding the app to the list there (`AXIsProcessTrustedWithOptions`), and offers its icon to
drag in should it be missing; it warns when the app runs from the disk image. The app starts once
access is on, and the window comes back if access is turned off. The bundle is signed with your
first Apple Development / Developer ID identity so the grant survives rebuilds. With ad-hoc signing
you'd have to re-grant after every build (the welcome window explains how to remove and re-add the
app).

## How it works

- `AccessibilityWatcher` follows whether the app has Accessibility access; `WelcomeWindowController`
  shows the guide until it does, and `AppDelegate` starts everything else once it has.
- `HoverMonitor` listens for global mouse-moved events and waits for the cursor to rest (150 ms;
  never under 50). It doesn't look while previews wait for a key that isn't held, and stops listening
  while paused. On a web page it looks again a few times over the next two seconds while the cursor
  stays put, since Chromium fills in its accessibility tree after scrolling and loading, unless the
  first look found plain text; a second look can start a preview but never ends one, and clicks and
  key presses stop them.
- `HoverInspector` hit-tests with `AXUIElementCopyElementAtPosition` on a background queue (AX
  calls are synchronous IPC into the target app) and walks up to the enclosing link and web area.
  A look the cursor has moved on from is dropped before its slow parts, and excluded apps
  (`InspectionPolicy`) get only the hit-test.
- `MediaResolver` turns the hovered image or link into a `MediaSource` (`ImageRules` for full-size
  image URLs, `SiteLinks` for posts and videos), following `file:` URLs only from local pages, and
  to the local network (`LocalNetwork`: loopback, private ranges, `.local`, and IPv4 addresses
  inside NAT64 and 6to4 ones) only from local pages, redirects included, apart from a video's,
  which AVPlayer follows itself. `ImageLoader` sends and keeps cookies only for the sites in
  `MediaSite` (`LimitedDownloader` handles them itself, from the shared storage), so an image host
  can't track the user across sites; AVPlayer keeps its own. `MediaFetcher` does any
  lookup the site needs (`SiteAPIs`, `RedditGallery`), giving `Media`: one item or an album, with
  web addresses only; lookups that fail are remembered for a minute. Nothing is previewed over a
  video the page shows (WebKit gives videos their URL; Chromium shows them as plain groups, found
  through its search for graphics), or over an image it already shows about as large as a preview
  could be, unless it's from a post holding more. A photo outside any link, as in Instagram's feed,
  takes its post from the nearest link to one before it in the page (the time in the post's header),
  through the engine's search for links. `AppKind` tells browsers and email apps apart from what
  they declare they open, and `OtherAppsPolicy` decides what may load outside browsers.
- `PreviewController` shows items in `PreviewPanel`: images via `ImageLoader` (downloaded through
  `LimitedDownloader`, which stops at the size limit, sized up before decoding by
  `ImageDecoder.Picture`, and downsampled off the main thread), videos
  via `VideoPlayback` (AVPlayer). A spinner stands in for a preview that takes a moment. A small
  click-through notch sits under the cursor and joins it to the preview (`PreviewGeometry`); moving
  off the notch any way but onto the preview ends the hover at once. Clicking, Esc, and switching
  apps or Spaces end it too, as does scrolling anywhere else. `ScrollTap` (an active event tap)
  hands scroll events over the notch or preview to the controller and swallows the ones it uses: on
  the notch, a video's volume, shown on `VolumeRockerView` above the notch, whose space counts as
  the notch; on the video, its position.
- In Finder, `FinderItem` finds the hovered item: each one is an element with `AXFilename` and a
  file reference `AXURL`, reached from other cells of a list row or the label under an icon through
  the row or the item's group. `FileDetails` reads the card's details from Spotlight and Finder's
  records first, so protected folders aren't opened just to describe a file, and reads nothing of a
  file that's only in the cloud (the app also turns off downloading such files on read, in
  `main.swift`); `FileStatus` covers tags, iCloud, quarantine, and aliases, `ZipSummary` reads a
  zip's central directory, `AppBundleInfo` an app's Info.plist and signature (a developer's name only
  from a certificate Apple issued), and `GitRepository` a
  repository's branch and remote from its `.git`. Git itself is never run: a repository's settings
  can make it run commands, and a hovered folder can come from anywhere. Only regular files are
  opened (`FileDetails.isRegularFile`): a named pipe would wait forever for a writer. `FileUsers` finds apps
  whose windows show the file (`AXDocument`) and processes that hold it open, map it, or work in it
  (`proc_listpidspath`), and quits them. The card grows as slower details fill in
  (`CardHostingView`). `MediaMetadata` reads audio and video files' own tags (ID3, iTunes,
  QuickTime) and tracks with AVFoundation, since Spotlight often hasn't. Images, videos, and audio
  show large in `FileMediaCardView`, with the card beside or below them as `FileMediaLayout`
  decides; songs play through `VideoPlayback` too. Songs and videos have a `TransportBar` under them,
  following the player through a `MediaTransport`; AVKit's own controls show only while the cursor is
  on the video, and there it's in Finder. `Tests/HoverEnhanceTests/Fixtures` holds tiny
  tagged media for the tests, with the commands that made them.
- The weather popup: `WeatherTrigger` matches Apple's Weather menu bar item, and `PreviewController`
  hangs a `WeatherPopupView` under it rather than beside the cursor
  (`PreviewGeometry.dropDownFrame`, with a tab from the item down to it). `WeatherPopupModel`
  resolves the place set in Settings (`WeatherLocationChoice`: a `WeatherPlace` found with MapKit's
  search, or `CurrentLocation` through Core Location, which the hardened runtime allows only with
  the entitlement in `HoverEnhance.entitlements`), then gets a `WeatherReport`, always metric, from
  `WeatherService`, which keeps forecasts ten minutes and shows an older one at once while a new one
  loads. Each provider is a `WeatherSource` (`OpenMeteo`, `OpenWeatherMap`, `WeatherAPIcom`,
  `TomorrowIO`, `PirateWeather`, `AccuWeather`) fetching through `WeatherHTTP`, which turns HTTP
  failures into `WeatherError`s the popup explains; `NWSAlerts` adds US alerts when a provider has
  none. `AccuWeather` first trades the coordinate for AccuWeather's location key, kept in
  `AccuWeatherLocations` while the app runs, as every request counts against the user's plan, and
  asks only for what its cheapest plan includes. Its terms ask for its logo, linked, wherever its data
  shows, so the popup's footer has it. Keys are kept in the Keychain, and `WeatherUnits` writes
  values in the units chosen.
  `Tests/HoverEnhanceTests/Fixtures/weather` holds each provider's sample answers.
- The network popup: `SystemMenuExtra` matches the system's own menu bar items by `AXIdentifier`
  (`com.apple.menuextra.wifi`), in whichever Apple process hosts them (MenuBarAgent on macOS 27, Control
  Center before), and hangs `NetworkPopupView` under the Wi-Fi item as the weather hangs under its own.
  `NetworkReader` reads a `NetworkSnapshot` from configd (`SCDynamicStore`: the primary interface, router,
  DNS, addresses) and CoreWLAN (signal, noise, channel, rate, standard, security; the network's name only
  with Location Services), describing the connection under a VPN when a tunnel carries the traffic.
  `NetworkTraffic` turns the routing socket's 64-bit interface counters (`InterfaceCounters`) into speeds
  once a second while the popup is open, keeping a minute between hovers. `PublicAddressService` asks
  addr.fyi's `/json` for the public address, timing the TCP handshake of a fresh connection for the
  latency, and keeps the answer five minutes or until the network changes. Clicking a menu bar item opens
  its own menu, so `MenuBarClicks` keeps that item's popup away until a click elsewhere, a second click on
  it, or Esc closes the menu; this applies to the weather popup too. Settings → macOS
  (`MacOSSettingsView`) is where popups for the other system items (Sound, Control Center, the clock)
  will go.
- On YouTube itself, a link gets `CreatorCardView`, in YouTube's colors (`YouTubeTheme`). For a video,
  `MediaFetcher` reads its watch page (`YouTube.video(inPage:)`: `ytInitialPlayerResponse`, whose
  microformat has plain views, likes, and dates), which names its channel; oEmbed names it when that
  page can't be read. The channel's page gives the rest (`YouTube.channel(inPage:)`: `ytInitialData`,
  with the banner and verified check in its header). Subscribing goes through `YouTubeAPI` with the
  user's own Google client (`YouTubeAccount`). YouTube shows dislike counts only to a video's owner.
- `EmbedPlayer` hosts players in a web view loaded under an HTTPS origin (YouTube needs a
  Referer), with AirPlay and WebRTC off so nothing asks for local network access. Links clicked in a
  player open in the browser, and nothing else can take the page around the player elsewhere. A
  paused player is kept three minutes, for hovering its link again; one whose video never started
  (a script in an isolated world reports `playing`) is let go, since WebKit refuses its autoplay
  once suspended. WebKit counts suspensions, so each player is suspended once at most.
- `Updates` wraps Sparkle's updater; the Makefile bundles `Sparkle.framework` into the app (without
  the XPC services, which only sandboxed apps use) and signs it from the inside out.
- `GlobalShortcut` registers the pause shortcut as a Carbon hot key, which needs no further
  permission. `SkippedWebsites` matches the websites previews skip, by domain and subdomain, and
  `Webmail` the webmail pages skipped unless Settings → Sites allows them.
- `AppSettings` keeps settings in UserDefaults; code reads it where it's used, so changes apply at
  once. `SettingsWindowController` shows the SwiftUI tabs in `SettingsViews`.
- Reddit answers scripted requests with a JavaScript check; `WebPageLoader` passes it in an
  offscreen WebKit view and shares the cookie with URLSession.
- Chromium browsers and Electron apps only expose web content to accessibility on request, so the
  inspector sets `AXEnhancedUserInterface` (Chromium) or `AXManualAccessibility` (Electron) on them
  the first time it sees them, if previews could appear there (not excluded; Electron apps only with
  previews in other apps on). Chrome ignores `AXManualAccessibility`, so it gets the VoiceOver switch,
  which makes AppKit animate window moves made through accessibility; window managers such as
  Rectangle work around that. The inspector switches it back off when previews pause, the app is
  excluded, or HoverEnhance quits, unless VoiceOver is running or the switch was on before.

## Releases and updates

Updates go through [Sparkle](https://sparkle-project.org). The app reads the appcast attached to the
latest GitHub release (`SUFeedURL`, through `releases/latest/download/appcast.xml`) and installs an
update only if it's signed with the key whose public half is `SUPublicEDKey`. To release:

1. Raise `CFBundleShortVersionString` in `Resources/Info.plist` and add a dated entry for it to
   `CHANGELOG.md` (its bullets become the release notes, as HTML-escaped plain text in Sparkle's window).
2. Commit, then run `./bin/build-release.sh --upload`.
3. Bring [hoverenhance.com](https://hoverenhance.com) up to date: the `FALLBACK` release in its
   `src/routes/+page.server.ts`, and anything else the release changes. Merging doesn't publish it;
   run `npm run deploy` there once its main has the changes.

The script builds a universal app signed with Developer ID and the hardened runtime, puts it in a
signed DMG, notarizes and staples it, signs the update and the appcast, and publishes both as a
GitHub release tagged at the commit it built (as a draft first, so the latest release never lacks
either file). Without `--upload` it stops before publishing and prints the command that would.

It needs, once: a Developer ID Application certificate for team `G65RD22S57` (`TEAM_ID` in the
Makefile and the script; the release is refused if it's signed by any other team, and is signed by the
certificate's hash, so a renewed one alongside the old works); notary credentials saved with
`xcrun notarytool store-credentials notarytool-profile` (shared with LockAudio); the GitHub CLI,
signed in; a public repository, since release downloads from a private one need a GitHub login; and
the update signing key, in the login keychain under the account `HoverEnhance`
(`generate_keys --account HoverEnhance`, from `.build/artifacts/sparkle/Sparkle/bin`). Back that key
up (`generate_keys --account HoverEnhance -x <file>`): without it no update can ever be signed for
installed copies again.

Debug builds check only when asked, so a build from source isn't offered a release over itself.

## Icons and logos

`design/icons/appicon.svg` and `menubar.svg` are the sources; `./bin/render-icons.sh` renders them
into `Resources/AppIcon.icns` and `Resources/MenuBarIcon.png` with headless Chrome. It also renders
`design/logos/accuweather.svg` and `accuweather-dark.svg`, AccuWeather's small-space logo for light
and dark backgrounds from its
[brand guidelines](https://developer.accuweather.com/documentation/brand-guidelines)
(`AW_RGB_Small_R.svg` and `AW_RGB_Rev_Small_R.svg`), into `Resources/AccuWeatherLogo.png` and
`AccuWeatherLogoDark.png`.
