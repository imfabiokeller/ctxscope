import AppKit
import ScopeCore
import ScopeUI
import SwiftUI

// Traffic lights stay where the system puts them: moving them clips the buttons, and a
// toolbar tall enough to centre them swallows clicks on trailing controls on macOS 26.
@MainActor
final class InstrumentWindowController: NSObject, NSWindowDelegate {
  private let model: InstrumentModel
  private let themes: ThemeStore
  private let window: NSWindow
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
    // Hidden, but Mission Control and the accessibility tree read it.
    window.title = "ctxscope"
    window.isMovableByWindowBackground = false
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    // A window built in code releases itself on close; the controller owns it too.
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
    .ignoresSafeArea(.container, edges: .top)
  }

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

  func windowDidMiniaturize(_ notification: Notification) {
    onHide?()
  }

  func windowDidDeminiaturize(_ notification: Notification) {
    onShow?()
  }

  static func save(_ data: Data, name: String) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      do {
        try data.write(to: url)
      } catch {
        let alert = NSAlert(error: error)
        alert.messageText = "ctxscope could not write the export."
        alert.runModal()
      }
    }
  }
}

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
