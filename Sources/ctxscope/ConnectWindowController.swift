import AppKit
import ScopeConnect
import ScopeUI
import SwiftUI

/// The small window the Connect item opens.
///
/// A window rather than a sheet: the instrument window is not always open, and
/// the menu bar item has to be able to open this on its own.
@MainActor
final class ConnectWindowController: NSObject, NSWindowDelegate {
  private let window: NSWindow
  private let model: ConnectModel

  init(home: ClaudeHome, listening: UInt16?, themes: ThemeStore) {
    model = ConnectModel(home: home, listening: listening)
    window = NSWindow(
      contentRect: NSRect(origin: .zero, size: Metrics.standard.connect.size),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Connect"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(
      rootView: ConnectPanel(model: model).environment(\.theme, themes.theme))
    super.init()
    window.delegate = self
  }

  /// Called when the window has gone, so the app can let go of it.
  var onClose: (() -> Void)?

  func show(listening: UInt16?) {
    model.listener(port: listening)
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    onClose?()
  }
}
