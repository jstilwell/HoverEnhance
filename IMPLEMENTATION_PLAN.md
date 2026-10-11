# Notch volume and Finder media previews

Scrolling on the notch changes a video's volume, shown on a rocker beside it, while scrolling on the
video moves through it. In Finder, images, videos, and audio get a large preview with their details
beside or below, and audio and video show the metadata in the file itself.

Still to check live from the review fixes: the welcome window with access removed and dragged back
in; the panel's material, fades, and spinner; Load Anyway; a link clicked in an embedded player; the
other-apps sheet; Subscribe while signed in; and 0.1.0 updating itself to 0.1.1.

## Stage 1: Notch volume and rocker
**Goal**: Scrolling on the notch sets the volume; on the video, it moves through it.
**Success Criteria**: During a video preview a volume rocker sits above the notch against the
preview's edge (below it when there's no room above), showing the level and mute, and following the
player's own controls. Scrolling on the notch or the rocker changes the volume; on the video, the
position. Settings → Video sets each separately (defaults: notch volume, video position). Moving from
the notch onto the rocker keeps the preview.
**Tests**: Rocker geometry above and below the notch, on either side; the new setting's default and
persistence; existing scroll tests.
**Status**: Complete

## Stage 2: Metadata from the file
**Goal**: Audio and video show what their files say about them, not only what Spotlight indexed.
**Success Criteria**: Audio: title, artist, album, album artist, composer, genre, year, track and
disc, and artwork, from ID3 and iTunes tags. Video: title, recording date and device, frame rate,
HDR, and audio channels. Read with AVFoundation; each detail has a switch in Settings → Finder.
**Tests**: Committed fixtures with neutral tags (an MP3 with ID3 and artwork, an M4A, a short MP4),
made once with ffmpeg; reading each field; files without tags give nothing.
**Status**: Complete

## Stage 3: Large Finder previews
**Goal**: Images, videos, and audio in Finder preview large, with their details.
**Success Criteria**: Images show large; videos play, with the notch volume and rocker; audio shows its
artwork (or a placeholder) with a play button, or plays at once when Settings → Finder says so. The
details go beside the media or below it, whichever leaves the media larger. Other files and folders
keep the card. A switch in Settings → Finder turns large previews off.
**Tests**: Layout choice (beside or below) for wide, tall, and square media in various rooms; the new
settings; visual checks rendered offscreen.
**Status**: Not Started

## Stage 4: Docs and release
**Goal**: README, CHANGELOG, and docs describe the new behavior.
**Success Criteria**: README and the 0.2.0 changelog entry say what users notice; docs/DEVELOPMENT.md
covers the new pieces.
**Tests**: Full suite; a release build with no warnings.
**Status**: Not Started
