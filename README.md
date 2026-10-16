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
- **YouTube cards**: on YouTube, rest on a video title for its length, views, likes, date, and who
  made it, or on a channel name for the channel's banner and numbers.
- **Weather**: rest on the Weather item in the menu bar for the forecast it doesn't show: the next 24
  hours, ten days, wind, humidity, pressure, UV, air quality, sun and moon, and alerts. Open-Meteo by
  default, or OpenWeatherMap, WeatherAPI.com, Tomorrow.io, Pirate Weather, or AccuWeather with your
  own key. AccuWeather adds pollen, the temperature in the shade, the change since yesterday, and a
  forecaster's summary; its key needs a paid plan after a 14-day trial.
- **Network**: rest on the Wi-Fi item in the menu bar for the connection, live download and upload
  speeds, local and public IP addresses, router, DNS, provider, latency, and the Wi-Fi signal, channel,
  and security. Click any of it to copy it.
- **Finder**: rest on a file or folder for its path, size, dates, where it came from, and which apps
  are using it. Images, songs, and videos show large beside their details, including what songs' and
  videos' own tags say, with play, mute, and a scrubber showing the time under songs and videos.
  Click any detail to copy it.

Images the page already shows large are left alone unless their post has more photos, as are videos
it's already playing. Move away, click, press Esc, or switch apps or Spaces, and the preview is
gone.

## Install

Download the latest DMG from [Releases](https://github.com/jstilwell/HoverEnhance/releases), open
it, and drag HoverEnhance to Applications. It's signed, notarized, and updates itself.

A welcome window walks you through turning on Accessibility access, which lets HoverEnhance see
what's under the cursor: it adds HoverEnhance to the list, and you switch it on. Requires macOS 14
or later.

## Privacy

- **Only what you hover**: HoverEnhance reads the thing under the cursor, never what you type.
- **Only where you point**: it contacts the sites behind what you hover, GitHub to check for
  updates, addr.fyi for the network popup's public address, and Google only if you sign in to
  subscribe to YouTube channels.
- **Not your network**: links and images on a web page that point at your router, printer, or anything
  else on your local network are left alone.
- **No tracking cookies**: images from anywhere but the sites under Settings → Sites load without
  cookies, so they can't follow you from site to site.
- **Weather where you say**: nothing is looked up until you pick a place or allow your location, which
  goes to the weather provider you choose rounded to about a kilometer (and, in the US, to the
  National Weather Service for alerts when your provider has none, unless you turn that off).
- **Network from the Mac**: the network popup reads everything from your Mac except the public IP
  address, which comes from [addr.fyi](https://addr.fyi), also run by HoverEnhance's maintainer (it sees
  only that address; turn it off in Settings).
- **Browsers by default**: links in other apps, like Mail, load nothing unless you allow it in Settings.
- **Not your email**: no previews on webmail, like Gmail or Outlook, where a link can tell its sender
  you read the message. Settings can turn them back on.
- **No surprise downloads**: images over 25 MB (adjustable) wait for you to click Load Anyway, and
  files only in iCloud stay there.

## Settings

From the menu bar icon: a shortcut that pauses previews from any app, when they appear (always, or
while holding a key), the hover delay, apps and websites to skip, what file cards show, preview size,
video playback, the weather's provider, place, and units, and in a macOS tab, the network popup. The menu can also skip the website
you're on.

## Building from source

`./bin/run.sh` builds and launches it (requires Xcode). See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
for tests, releases, and how it works.

## License

[MIT](LICENSE). Includes [Sparkle](https://github.com/sparkle-project/Sparkle) for updates, under its
own MIT license.
