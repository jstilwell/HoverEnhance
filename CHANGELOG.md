# Changelog

All notable changes to this project will be documented in this file.

## 0.6.0 - 10-15-2026

### Added

- Rest on the Wi-Fi item in the menu bar to see your network at a glance: the connection, live download and upload speeds with the last minute charted, local and public IP addresses, router, DNS, internet provider, latency, and the Wi-Fi signal, noise, channel, rate, standard, and security.
- Click any address or name in the network popup to copy it.
- A new macOS tab in Settings turns the network popup on or off, and the public IP lookup from addr.fyi.

### Fixed

- Clicking the Weather item in the menu bar opens its menu without the forecast popup appearing over it.

## 0.5.0 - 10-12-2026

### Added

- Songs and videos in Finder previews have controls under them: play and pause, a scrubber with the time played and left, and mute.
- Click a Finder video, or a song's artwork, to play or pause it.
- On YouTube, resting on a video title shows the video first: its thumbnail and length, title, views, likes, upload date, category, and the start of its description, then who made it.
- YouTube channel cards show the channel's banner and its verified check.

### Changed

- YouTube cards look like YouTube, in its light or dark colors, with its rounded buttons and counts like "1.64M subscribers".
- A YouTube card's Subscribe button says Subscribe when you're signed out, as on YouTube, and opens Settings to sign in.
- Unsubscribing from a YouTube card takes a second click, on Unsubscribe after Subscribed.

### Fixed

- A YouTube, Vimeo, TikTok, or Twitch video rested on again picks up where it was, instead of stopping on a play button that did nothing when clicked.
- A video whose preview closed before it started plays on its own the next time.

## 0.4.0 - 10-12-2026

### Added

- Choose AccuWeather for the weather popup in Settings → Weather, with your own key, which needs a paid plan after a 14-day free trial.
- With AccuWeather, the weather popup shows today's pollen, how warm it feels in the shade, how today compares with yesterday, and a forecaster's summary of the days ahead.
- Turn the weather popup's pollen off in Settings → Weather.

### Changed

- The weather popup's hourly forecast says how many hours it covers, as AccuWeather's covers 12.

## 0.3.0 - 10-12-2026

### Added

- Rest on the Weather item in the menu bar for a full forecast under it: the next 24 hours, ten days, wind, humidity, pressure, UV, air quality, sun and moon, and alerts, from Open-Meteo or a provider you choose in Settings → Weather.
- Press Esc to close any preview.
- Set a shortcut in Settings → General to show or hide previews from any app.
- Skip previews on websites you choose, in Settings → Sites, or from the menu bar for the one you're on.
- A preview that couldn't load says so for a moment, instead of its spinner just vanishing.
- The welcome window warns when HoverEnhance is running from its disk image, where its access wouldn't last.
- The welcome window's last screen says how to zoom, step through albums, and change a video's volume.

### Changed

- Finder cards no longer count a Git repository's uncommitted changes: that meant running Git, which a downloaded repository could use to run its own commands.
- Open System Settings in the welcome window adds HoverEnhance to the Accessibility list, so you only switch it on.
- Pausing previews, quitting, or excluding Chrome or an Electron app switches off the accessibility mode HoverEnhance turned on there, so window managers like Rectangle stop animating its windows.
- Excluded apps, and apps that can't show previews, aren't looked into at all.
- The shortest hover delay is 50 ms.
- Load Anyway stops at 1 GB.

### Fixed

- Resting on a link made with an absurdly long video time or post number no longer crashes HoverEnhance.
- An image whose server claims an impossible size no longer crashes HoverEnhance.
- Links and images on a web page that point at your router, printer, or anything else on your local network no longer load, as browsers already refuse.
- Resting on a file that's only in iCloud, or in Dropbox and the like, no longer downloads it.
- An image too large to decode safely is skipped instead of stalling HoverEnhance, and an animation with huge frames shows as a still.
- A video player in a preview can no longer turn itself into some other web page.
- Finder cards show invisible characters in names and paths as codes, so a fake ".pdf" that's really an app can't pass for a document.
- A Finder card's "Signed by" checks every file the signature covers, and says when an app was changed since, or was too big to check in time.
- Cut, copy, paste, and undo work in Settings' text fields, such as the YouTube client ID and secret.
- Previews in other apps no longer stop for good when they need a key and previews appear except while holding it.
- Pressing ⌘ or another modifier no longer counts as the activation key.
- Switching Spaces closes the preview.
- A preview whose site doesn't answer gives up after about 10 seconds instead of a minute.
- HoverEnhance asks the browser about a resting cursor less often, and not at all while previews wait for a key you aren't holding.
- Large images download faster, album photos aren't downloaded twice, and a link that just failed isn't fetched again right away.
- A paused video player frees its memory a few minutes after its preview closes.
- Multi-page TIFFs and icon files show their largest picture.

## 0.2.0 - 10-11-2026

### Added

- Scroll on the notch under the cursor to change a video's volume, shown on a rocker beside it; scroll on the video to move through it.
- In Finder, images, videos, and audio show large, with their details beside or below.
- Songs in Finder show their artwork and play at a click, or right away if you turn that on.
- Songs and videos in Finder show what their own tags say: title, artist, album, album artist, composer, genre, year, track, and disc, and when and with what a video was recorded.
- Finder cards show a video's frame rate and HDR, and the sample rate and channels of its sound.
- Multi-photo posts in Instagram's feed open as an album at the photo you're on, to scroll through without the arrows.

### Changed

- Scrolling on a video moves it 2 seconds a step, wheel or trackpad alike, and Settings → Video can change that.
- The menu starts with the app's version.

### Fixed

- No preview pops up over a video the page is already playing, as on Instagram, or over an image it already shows large.
- Instagram albums no longer show as one photo after the cursor passes over them while they load.
- Previews come up more reliably when the cursor stops on a page still filling in, as just after scrolling.
- Clearing the image cache in Settings shows the new size right away.

## 0.1.1 - 10-11-2026

### Fixed

- A behind-the-scenes fix; nothing changes in how HoverEnhance works.

## 0.1.0 - 10-11-2026

### Added

- Rest on an image or image link in your browser to see it full size, and scroll through galleries and multi-photo posts.
- Videos from Reddit, X, Bluesky, Instagram, Streamable, and Imgur play in the preview; YouTube, Vimeo, TikTok, and Twitch play in their own players.
- On YouTube, rest on a video title or channel name to see its creator, and subscribe once you sign in.
- In Finder, rest on a file or folder to see its path, details, and which apps are using it.
- Images over your download limit show their size first, with Load Anyway.
- Links in apps other than browsers load nothing unless you allow it, with options to skip email apps, stick to known sites, or wait for a key.
- A welcome window walks you through turning on Accessibility access.
- HoverEnhance updates itself.
