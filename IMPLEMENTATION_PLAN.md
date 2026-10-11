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

## Stage 4: Browser sign-in option
**Goal**: An easier alternative to the Google API: subscribe through the user's signed-in YouTube tab.
**Success Criteria**: Settings → Accounts offers Google API (recommended) or Your browser, with setup
steps and a Test button; in browser mode the card checks and changes subscriptions by running
YouTube's own web requests in the YouTube tab via AppleScript (Safari, and Chromium browsers with a
scripting dictionary); setup problems (JavaScript from Apple Events off, Automation denied, no YouTube
tab, signed out) explain the fix.
**Tests**: AppleScript and JavaScript generation (escaping, JS parsed by JavaScriptCore, AppleScript
compiled against Helium and Safari); osascript error mapping; result parsing. Still to do: a live
check in the user's browser (needs the browser setting and the Automation prompt answered).
**Status**: In Progress
