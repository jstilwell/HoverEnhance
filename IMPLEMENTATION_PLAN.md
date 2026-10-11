# Albums and video previews

Image previews (resolve → load → panel) are done. Next: multi-item albums and playable video.

## Stage 1: Albums
**Goal**: Preview multi-image posts as albums, starting with Reddit galleries.
**Success Criteria**: Hovering a reddit.com/gallery link shows the first image with a "1/5" counter
at the top left; scrolling while the preview is up steps through the images without scrolling the
page; the next image is prefetched.
**Tests**: Gallery page parsing (order, de-duplication, full-size URLs); link → source resolution;
manual check on r/pics "Mountain lake!" (gallery case on `Tests/Manual/preview-test.html`).
**Status**: Complete

## Stage 2: Native video
**Goal**: Play videos in the preview with AVFoundation.
**Success Criteria**: Streamable, v.redd.it (HLS), Imgur gifv/mp4, direct .mp4/.m3u8 links, X/Twitter
and Bluesky posts play; moving onto the preview keeps it open and shows playback/volume controls;
reopening a video resumes where it stopped; mute/volume choice is remembered.
**Tests**: Per-site resolution unit tests; live API smoke tests; manual hover/controls/resume checks
(video cases on `Tests/Manual/preview-test.html`). Imgur gifv is rule-only (no live sample).
**Status**: Complete

## Stage 3: Embedded players
**Goal**: Sites without a playable stream play through their own embed player in a web view.
**Success Criteria**: YouTube, Vimeo, TikTok, and Twitch clip links play in the preview. (Instagram moved to
native playback: its embed page lists the post's images and video, and its player shows an error page
for posts whose owners turned embedding off.)
**Tests**: URL → embed unit tests; manual check per site (embed cases on `Tests/Manual/preview-test.html`).
**Status**: Complete

## Stage 4: Polish
**Goal**: Rough edges found along the way.
**Success Criteria**: Loading indicator, hold-a-modifier mode, settings window if the menu outgrows itself.
**Tests**: Manual.
**Status**: Not Started
