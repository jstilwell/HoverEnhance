# Review fixes

Fixes from a review of the whole app: privacy and security, first run, preview polish, settings, and
packaging. Carried over from the YouTube creator card plan: subscribing still needs a signed-in check
with the user's own OAuth client.

## Stage 1: Privacy and security
**Goal**: Hovering can't leak what's on screen or reach places a web page shouldn't.
**Success Criteria**: Hover summaries reach the log only while the inspector is on, and URLs and text
are private outside debug builds; `file:` URLs are followed only from local pages; network previews
happen only in browsers unless Settings → General allows other apps, and turning that on offers safety
options (skip email apps, known sites only, only while holding a key); Vimeo hashes are checked like
other IDs; the sign-in listener ignores replies with the wrong state; Keychain write failures surface;
Quit and Force Quit never signal a process that reused the pid.
**Tests**: `file:` links from web and local pages; browser and email app detection from Info.plist
contents; resolver results in browsers, other apps, email apps, and for unknown sites; Vimeo hash
validation; loopback ignores a wrong state and still catches the right one; a recycled pid isn't
signalled; new settings persist.
**Status**: Complete

## Stage 2: Image size limit
**Goal**: Large images don't download unasked.
**Success Criteria**: Settings → Previews sets the largest image to download; a larger one (by its
Content-Length, or by bytes received when there's none) stops downloading and the preview says how big
it is, with Load Anyway, which loads it.
**Tests**: Capped downloads through a stub URLProtocol: under the limit, over by Content-Length, over
without one; the setting persists.
**Status**: Not Started

## Stage 3: Welcome window
**Goal**: Nothing runs until Accessibility is on, and the first thing seen explains how to turn it on.
**Success Criteria**: Without Accessibility, launch shows only a welcome window: what the app does, a
button to open the Accessibility settings, the app icon to drag into the list, and how to remove and
re-add the app when it's listed but not working. Granting starts the app and says where it lives.
Closing the window before then quits. Losing access while running brings the window back.
**Tests**: The window's state follows trust (checked through an injected trust check); manual check
of the drag into System Settings and of granting and revoking.
**Status**: Not Started

## Stage 4: Preview polish
**Goal**: Previews feel finished.
**Success Criteria**: A spinner in the notch while a preview loads; previews fade in and out (not
with Reduce Motion); panels use a system material and follow light and dark mode; links in embedded
players open in the browser; the menu bar icon dims while previews are off; Pause and Enable Previews
become one Show Previews item, and nothing is inspected while previews and the inspector are both off.
**Tests**: Existing geometry and scroll tests; visual checks rendered offscreen.
**Status**: Not Started

## Stage 5: Settings and packaging
**Goal**: The app looks and ships like a finished one.
**Success Criteria**: Settings tabs share one height and scroll; Accessibility status and Clear
website data update live; About shows version, build, and the repository; tabs are opened by an enum;
an app icon; Info.plist has copyright and category; `make release` signs with the hardened runtime and
notarizes; README matches.
**Tests**: Settings tests; `make app` and the release signing step run; `codesign --verify`.
**Status**: Not Started
