# Finder file cards

Hovering a file or folder in Finder (list, icon, column, and gallery views, and the desktop) shows a
card with its path and a button to copy it, details about it, and the apps using it, with a way to
quit them. A Finder tab in Settings picks what the card shows.

Finder exposes each item as one element carrying `AXFilename` and a file reference `AXURL` (the name
in list and column view, the icon in icon and gallery view, desktop icons). The rest of a list row
and the label area of an icon lead to it through their `AXRow` or item `AXGroup`.

## Stage 1: Find the hovered file
**Goal**: The inspector reports the file or folder under the cursor in Finder.
**Success Criteria**: Hovering any part of a list row, an icon or its label, a column-view item, a
gallery thumbnail, or a desktop icon gives the item's path; desktop stacks, the sidebar, and empty
space give none; the inspector shows the path.
**Tests**: Item lookup over a fake accessibility tree (name, other cells of a row, icon group,
desktop group with many items, stack without a URL); file reference URLs resolve to paths.
**Status**: Complete

## Stage 2: File card with the path
**Goal**: The card appears beside the cursor with the item's icon, name, and path, and copies the path.
**Success Criteria**: The card follows the notch rules (leaving ends it, clicking dismisses it);
scrolling passes through to Finder; a Finder tab turns cards on and off, sets their delay, and picks
how the path is copied (full, with ~, quoted for the shell).
**Tests**: Path styles (home prefix only at a folder boundary, quoting only when needed, embedded
quotes); Finder settings defaults and persistence; resolver and filter for file sources.
**Status**: Complete

## Stage 3: Details
**Goal**: Kind, size, dates, image dimensions, audio and video length, and where a download came from.
**Success Criteria**: Each detail has its own switch; folders skip size; details missing from a file
are left out rather than shown empty.
**Tests**: Details of temp files (size, dates, kind), a generated PNG's dimensions, and a where-from
attribute written to a temp file; parsing where-from lists (prefers the page over the file URL).
**Status**: Complete

## Stage 4: Apps using it, and quitting them
**Goal**: The card lists apps with it open in a window, processes holding it open or working in the
folder, and the running app for an app bundle; each can be quit.
**Success Criteria**: The list fills in after the card appears and the card grows to fit; Quit asks
for a second click, quits politely, and offers Force Quit if the process is still running; a Finder
setting hides the quit buttons.
**Tests**: The scan finds a file held open and a working folder (this test process); quitting a child
process ends it; cards rendered offscreen with the list loaded and Quit confirming. Still to do: a
live check in Finder (the list filling in and the card growing; Quit on a real app).
**Status**: In Progress

Stages 5–8 borrow ideas from FinderHover (MIT), written fresh with in-process APIs rather than
spawning a tool per hover. Its file detection, long tail of formats, file notes, layout editor, and
appearance settings are left out.

## Stage 5: Settings per detail, and when cards appear
**Goal**: Every detail is its own switch, grouped like the card; cards can skip the desktop and
folders; a key press closes the card (Quick Look, renaming, typing); clicking a detail copies it.
**Success Criteria**: Turning off a detail hides it and skips reading it; Restore Defaults brings back
the defaults; Space or Return over a card closes it until the cursor moves to another item.
**Tests**: Field settings defaults and persistence; filter for desktop items and folders (Finder writes
folder URLs with a trailing slash, packages without); offscreen render of the settings tab. Still to
do: a live check that Space and Return close a card, which relies on macOS passing key presses to an
app with Accessibility access alone.
**Status**: In Progress

## Stage 6: Thumbnail and system facts
**Goal**: A Quick Look thumbnail in place of the icon; Finder tags with their colors; iCloud status;
who downloaded a file and when; where an alias or symlink points, copyable like the path.
**Success Criteria**: The thumbnail replaces the icon without moving anything; each fact appears only
when the file has it.
**Tests**: Tags with colors from the tags attribute; quarantine record parsed from the attribute;
symlink and alias targets, including a missing one; offscreen render.
**Status**: Complete

## Stage 7: Media details and zip contents
**Goal**: Camera, lens, and exposure for photos; codecs and bit rate for audio and video; artist and
album for music (all from Spotlight); file count, unpacked size, and encryption for zip files.
**Success Criteria**: Values are formatted as photographers read them (ƒ/1.8, 1/120 s, ISO 50,
26 mm); zip summaries handle Zip64 and skip `__MACOSX`; large central directories are left alone.
**Tests**: Exposure and bit-rate formatting; zip summaries of archives made with `zip` (files,
folders, `__MACOSX`, encrypted), Zip64 fields, and truncated files.
**Status**: Complete

## Stage 8: Apps and Git
**Goal**: For app bundles, version, bundle ID, architectures, minimum macOS, and code signature;
for Git repositories, branch, remote, and uncommitted changes.
**Success Criteria**: Signature and changes fill in after the card appears; Git runs the real binary
(never the `/usr/bin/git` stub, which offers to install developer tools), with a timeout and without
taking Git's locks; repos without a remote or on a detached HEAD read sensibly.
**Tests**: Info of a system app; signatures of a system app, an ad-hoc signed and an unsigned binary;
HEAD and config parsing (branch, detached, worktree `.git` file, remotes); changes in a temp repo.
**Status**: Complete

# YouTube creator card

Previews, albums, video, embeds, the notch, settings, and scroll handling are done. On youtube.com
itself, hovering a text link (a video title or channel name) shows a card about the creator instead
of a preview; hovering media (thumbnails, YouTube's own hover previews, avatars) shows nothing.

Left over from earlier polish: a loading indicator for slow previews.

## Stage 1: Creator card
**Goal**: The card, with info that needs no sign-in.
**Success Criteria**: On youtube.com, text links to videos or channels show avatar, name, handle,
subscriber and video counts, description, and Open Channel; thumbnails, avatars, and YouTube's
hover previews show nothing; a Creator cards switch in Settings.
**Tests**: Link → channel reference; channel page and oEmbed parsing; "on text" detection; manual
check on a YouTube search page (title and channel name show the card; thumbnail and avatar don't).
**Status**: Complete

## Stage 2: YouTube sign-in
**Goal**: Sign in to YouTube with the user's own Google Cloud OAuth client.
**Success Criteria**: Settings → Accounts takes a client ID and secret, signs in through the browser
(PKCE, loopback redirect), keeps the refresh token in the Keychain, refreshes access tokens, and
signs out (revoking the token).
**Tests**: PKCE and URL building; loopback redirect handling; token response parsing; error paths
against Google's endpoints. A full sign-in needs the user's own OAuth client.
**Status**: Complete

## Stage 3: Subscribe and unsubscribe
**Goal**: The card's button subscribes or unsubscribes through the YouTube Data API.
**Success Criteria**: The card shows whether you're subscribed; the button toggles it; signed out, it
offers to sign in; API errors (quota, expired sign-in) show plainly.
**Tests**: API request building and response parsing; signed-out card checked live (the Sign In
button opens Settings → Accounts). Still to do: a signed-in check with the user's OAuth client.
**Status**: In Progress
