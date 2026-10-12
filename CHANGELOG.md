# Changelog

All notable changes to this project will be documented in this file.

## 0.3.0 - Unreleased

### Added

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
- A web page can no longer lead HoverEnhance to your router, printer, or anything else on your local network, which browsers already refuse.
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
