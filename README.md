# HoverEnhance

Rest your cursor on an image, video, or file and see it right there: full-size images and videos
in your browser, large previews and file details in Finder. A macOS menu bar app, no browser
extension needed.

## What it does

- **Images**: rest on a thumbnail or an image link and the full-size image appears. Scroll to zoom.
- **Albums**: Reddit galleries and multi-photo posts on X, Bluesky, and Instagram, in its feed too,
  from the photo you're on. Scroll to step through. Immune to smooth-scrolling glitches.
- **Videos**: Reddit, X, Bluesky, Instagram, Streamable, and Imgur clips play in the preview;
  YouTube, Vimeo, TikTok, and Twitch play in their own players. Scroll on the notch under the cursor
  for the volume, shown beside it, and on the video to move through it.
- **YouTube creators**: on YouTube, rest on a video title or channel name to see who made it.
- **Finder**: rest on a file or folder for its path, size, dates, where it came from, and which apps
  are using it. Images, videos, and audio show large beside their details, including what songs' and
  videos' own tags say. Click any detail to copy it.

Images the page already shows large are left alone unless their post has more photos, as are videos
it's already playing. Move away, click, or switch apps, and the preview is gone.

## Install

Download the latest DMG from [Releases](https://github.com/jstilwell/HoverEnhance/releases), open
it, and drag HoverEnhance to Applications. It's signed, notarized, and updates itself.

A welcome window walks you through turning on Accessibility access, which lets HoverEnhance see
what's under the cursor. Requires macOS 14 or later.

## Privacy

- **Only what you hover**: HoverEnhance reads the thing under the cursor, never what you type.
- **Only where you point**: it contacts the sites behind what you hover, GitHub to check for
  updates, and Google only if you sign in to subscribe to YouTube channels.
- **Not your network**: a web page can't make it reach your router, printer, or anything else on your
  local network.
- **Browsers by default**: links in other apps, like Mail, load nothing unless you allow it in Settings.
- **No surprise downloads**: images over 25 MB (adjustable) wait for you to click Load Anyway, and
  files only in iCloud stay there.

## Settings

From the menu bar icon: when previews appear (always, or while holding a key), the hover delay,
apps and sites to skip, what file cards show, preview size, and video playback.

## Building from source

`./bin/run.sh` builds and launches it (requires Xcode). See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
for tests, releases, and how it works.

## License

[MIT](LICENSE). Includes [Sparkle](https://github.com/sparkle-project/Sparkle) for updates, under its
own MIT license.
