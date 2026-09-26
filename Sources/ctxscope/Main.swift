import AppKit

@main
enum Main {
  static func main() {
    Diagnostics.runIfAsked()
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }
}
