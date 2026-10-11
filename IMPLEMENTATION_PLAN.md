# Image preview

HoverZoom-style previews: when the cursor rests on an image (or a link to one), show the
full-size image in a floating panel beside the cursor.

## Stage 1: Find the image and its full-size URL
**Goal**: From a hover result, produce an ordered list of candidate URLs for the full-size image.
**Success Criteria**: Hovering an image, an overlay on top of an image, or a link to an image yields
candidates; known thumbnail URLs are rewritten to full size with the original as a fallback.
**Tests**: Rules for Bluesky, Reddit, Imgur, Wikimedia, YouTube, Letterboxd; direct image links;
non-image links produce nothing; candidates are de-duplicated. Manual page: `Tests/Manual/preview-test.html`.
**Status**: Complete

## Stage 2: Load and decode
**Goal**: Fetch candidates in order and decode the first that works, off the main thread.
**Success Criteria**: Falls through 404s; downsamples to screen size; animated GIFs stay animated;
repeat hovers hit the cache; cross-origin requests send only the page's origin as Referer.
**Tests**: Smoke test against live URLs (fallback chain, cache hit timing).
**Status**: In Progress

## Stage 3: Preview panel
**Goal**: Show the image beside the cursor and hide it at the right times.
**Success Criteria**: Fits the screen on the side with more room; skips images that aren't larger
than they already appear; hides when the cursor leaves the element, on scroll, and on click;
menu toggle for previews.
**Tests**: Manual: hover thumbnails in Safari/Chromium, scroll, click, move between images.
**Status**: Not Started

## Stage 4: More sites and polish
**Goal**: Broader coverage and nicer feel.
**Success Criteria**: More site rules (X/Twitter, Instagram, …), loading indicator, video/gifv,
hold-a-modifier mode, settings.
**Tests**: Per rule unit tests; manual checks.
**Status**: Not Started
