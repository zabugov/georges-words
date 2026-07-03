import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// A full app: Dock icon, app switcher entry, main window — plus the
// menu-bar status item as the always-there dictation indicator.
app.setActivationPolicy(.regular)
app.run()
