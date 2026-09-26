import AppKit

/// The entry point.
///
/// AppKit rather than a SwiftUI `App` scene, because the window this app shows
/// is not a document and is not always open: the menu bar item is what the app
/// is when no window is. A scene that opens itself cannot express that, and
/// the status item, the popover and the global shortcut are AppKit anyway.
@main
enum Main {
  static func main() {
    // The diagnostics run without a window and exit. They are how a bundled
    // build is shown to read a real session without anybody granting screen
    // capture.
    Diagnostics.runIfAsked()
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }
}
