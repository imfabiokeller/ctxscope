import AppKit
import ScopeCore
import ScopeUI
import SwiftUI

/// The instrument window: one bar and the instrument under it.
///
/// The window has no separate title bar. It is therefore
/// full-size content with a transparent, hidden title bar, and the top line of
/// the view is the title bar: it clears the traffic lights on the left and
/// drags the window by its empty parts. The traffic lights stay where the
/// system puts them, near the top of the bar rather than centred in it:
/// moving them by hand left half of each button outside its own view, and a
/// toolbar tall enough to centre them swallows clicks on the bar's trailing
/// controls on macOS 26. The title is still set, because that is what Mission
/// Control and the accessibility tree read.
@MainActor
final class InstrumentWindowController: NSObject, NSWindowDelegate {
  private let model: InstrumentModel
  private let themes: ThemeStore
  private let window: NSWindow
  /// Called when the window closes, so the application can drop its Dock icon, and
  /// when it is minimized or comes back.
  var onClose: (() -> Void)?
  var onHide: (() -> Void)?
  var onShow: (() -> Void)?

  init(model: InstrumentModel, themes: ThemeStore) {
    self.model = model
    self.themes = themes
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    super.init()
    window.title = "ctxscope"
    // The top bar is ours and drags the window itself, so the window does not
    // also drag from anywhere in its background.
    window.isMovableByWindowBackground = false
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    // A window built in code is released when it closes, and this one is also
    // owned by the controller: closing it then released it twice and the app
    // died in the next drain of the autorelease pool, which is exactly the
    // flow the menu bar item depends on.
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 1100, height: 720)
    window.setFrameAutosaveName("instrument")
    window.delegate = self
    window.contentView = NSHostingView(rootView: content)
    window.center()
  }

  private var content: some View {
    InstrumentRoot(
      model: model,
      themes: themes,
      onZoom: { [weak window] in window?.performZoom(nil) },
      onCopy: Self.copy
    )
    // The bar is the title bar, so it is drawn in the title bar's band.
    .ignoresSafeArea(.container, edges: .top)
  }

  /// The pasteboard belongs to the app, so the window's "Copy text" comes
  /// here.
  static func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  func show() {
    window.makeKeyAndOrderFront(nil)
  }

  func close() {
    window.close()
  }

  var isVisible: Bool { window.isVisible }

  func windowWillClose(_ notification: Notification) {
    onClose?()
  }

  /// A minimized window is not a window anybody is reading, so the menu bar
  /// comes back while it is in the Dock.
  func windowDidMiniaturize(_ notification: Notification) {
    onHide?()
  }

  func windowDidDeminiaturize(_ notification: Notification) {
    onShow?()
  }

  /// Writes where the person says and nowhere else: a label can name a file
  /// the session touched. The panel lives here because a view does not own a
  /// file dialog. `name` is what the panel suggests.
  static func save(_ data: Data, name: String) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      do {
        try data.write(to: url)
      } catch {
        // An export that did not happen has to say so: it used to fail into
        // nothing at all.
        let alert = NSAlert(error: error)
        alert.messageText = "ctxscope could not write the export."
        alert.runModal()
      }
    }
  }
}

/// The instrument, the theme it is drawn with, and the appearance the window
/// itself takes so that its own chrome matches.
private struct InstrumentRoot: View {
  let model: InstrumentModel
  let themes: ThemeStore
  let onZoom: () -> Void
  let onCopy: (String) -> Void

  var body: some View {
    InstrumentView(model: model, onZoom: onZoom, onCopy: onCopy)
      .environment(\.theme, themes.theme)
      .preferredColorScheme(themes.theme.appearance == .dark ? .dark : .light)
  }
}
