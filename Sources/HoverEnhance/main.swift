import AppKit

FileDetails.neverDownloadOnRead()
let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
// Menu-bar only (no Dock icon), even when the binary runs outside its .app bundle.
app.setActivationPolicy(.accessory)
app.run()
