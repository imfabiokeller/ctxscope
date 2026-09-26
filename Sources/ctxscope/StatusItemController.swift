import AppKit
import ScopeCore
import ScopeUI
import SwiftUI

/// The menu bar item: the mark and the context size of the session in
/// focus, the popover's panel on a click and a small menu on a secondary
/// click.
///
/// It shows the session in focus and nothing else. When that session is idle
/// the mark is dimmed and the number goes; with none in focus the mark is
/// outlined; when ctxscope is turned off the item is removed and the listener
/// goes on answering.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
  private let model: InstrumentModel
  private let themes: ThemeStore
  private var item: NSStatusItem?
  private var panel: StatusPanel?
  /// The reading on the bar now. The same reading is not drawn twice.
  private var shown: StatusReading??
  /// The picture on the bar now, which is what a cross-fade fades from.
  private var drawn: StatusFace?

  /// Whether the person asked the system for less motion. Asked on every
  /// change rather than once, because the setting can change while ctxscope
  /// runs; a test answers it itself rather than inheriting the machine's.
  var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  var onOpenWindow: (() -> Void)?
  var onConnect: (() -> Void)?
  var onTurnOff: (() -> Void)?
  /// One line at the top of the menu when there is something to say about the
  /// hooks.
  var hooksNote: (() -> String?)?

  init(model: InstrumentModel, themes: ThemeStore) {
    self.model = model
    self.themes = themes
    super.init()
  }

  /// Puts the item in the menu bar. Idempotent: turning ctxscope on again
  /// while it is already on changes nothing.
  func start() {
    guard item == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.target = self
    item.button?.action = #selector(clicked(_:))
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    item.button?.imagePosition = .imageLeading
    self.item = item
    refresh()
  }

  /// Takes it out again. The process stays, and so does the listener.
  func stop() {
    closePanel()
    if let item { NSStatusBar.system.removeStatusItem(item) }
    item = nil
    shown = nil
    drawn = nil
  }

  var isShowing: Bool { item != nil }
  var isPopoverShown: Bool { panel?.isShown == true }

  /// What a click does, for the launch diagnostic, which has no pointer. It
  /// never falls through to the menu: a menu that opens in a diagnostic waits
  /// for a click nobody is going to make.
  func openPopoverForDiagnostic() {
    guard let button = item?.button else { return }
    togglePanel(from: button)
  }

  func openWindowForDiagnostic() {
    closePanel()
    onOpenWindow?()
  }

  /// What the item is, for a diagnostic that has no screen to look at.
  func describe() -> String {
    guard let button = item?.button else { return "status item absent" }
    guard let image = button.image else { return "status item with no image" }
    let number = button.attributedTitle.string.isEmpty ? "no number" : button.attributedTitle.string
    let size = "\(Int(image.size.width))x\(Int(image.size.height))"
    let kind = image.isTemplate ? "template" : "colored"
    return "status item \(size) \(kind), \(number), length \(Int(button.frame.width))"
  }

  // MARK: what it shows

  /// Reads the session in focus and puts it in the bar. Called when anything
  /// the model shows changes, never on a timer.
  func refresh() {
    guard let button = item?.button else { return }
    refresh(on: button)
  }

  /// The same, on whatever it is drawing on. Everything it decides is here,
  /// so it can be decided in a test with no menu bar to hang an item in.
  func refresh(on button: any StatusButton) {
    let reading = StatusReading.make(from: model)
    guard shown != .some(reading) else { return }
    shown = .some(reading)
    let face = StatusFace(reading: reading)
    // One fade from the old picture to the new one. Added before the
    // drawing, because it is the drawing it fades.
    if StatusMotion.crossFades(
      from: drawn, to: face,
      reduceMotion: reducesMotion())
    {
      button.crossFade(seconds: StatusMotion.seconds)
    }
    drawn = face
    button.draw(
      image: StatusImage.make(face, ink: themes.theme.text.primary, screen: button.barScreen),
      number: MenuBarType.number(face.number),
      // The mark is a picture and the number is a title, so without a name
      // and a value the item is an unnamed button in the middle of the bar.
      tooltip: StatusVoice.tooltip(reading),
      value: StatusVoice.value(reading))
  }

  // MARK: clicks

  @objc private func clicked(_ sender: NSStatusBarButton) {
    let event = NSApp.currentEvent
    let secondary =
      event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
    if secondary { return showMenu(from: sender) }
    togglePanel(from: sender)
  }

  /// Opens the panel, or closes the one that is open.
  ///
  /// The panel takes the keyboard without activating ctxscope, so escape
  /// reaches it and whoever was in front stays in front: a person clicks
  /// the item in the middle of typing, and their next keystrokes still
  /// arrive where they were going.
  private func togglePanel(from button: NSStatusBarButton) {
    if isPopoverShown { return closePanel() }
    guard let bar = button.window else { return }
    // A session started somewhere else since the last scan is one somebody
    // may want to pick from here.
    model.reloadSessions()
    let panel = StatusPanel(content: popover, theme: themes.theme)
    panel.onClose = { [weak self] in self?.panelClosed() }
    self.panel = panel
    panel.show(under: bar)
  }

  /// The popover as the panel holds it, with what each of its buttons does.
  private var popover: some View {
    StatusPopoverHost(
      model: model, themes: themes, home: NSHomeDirectory(),
      actions: PopoverActions(
        // The window goes up before the panel closes, so the panel closing
        // sees it and leaves the front where it is.
        openWindow: { [weak self] in
          self?.onOpenWindow?()
          self?.closePanel()
        },
        pick: { [weak self] id in self?.model.focus(session: id) },
        copy: { text in
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
        },
        connect: { [weak self] in
          self?.onConnect?()
          self?.closePanel()
        },
        turnOff: { [weak self] in
          self?.closePanel()
          self?.onTurnOff?()
        },
        quit: { NSApp.terminate(nil) }))
  }

  func closePanel() {
    panel?.close()
    // A panel that was never shown has nothing to say when it closes.
    if panel != nil { panelClosed() }
  }

  /// However the panel closed: escape, a click elsewhere, a button in it, or
  /// the application stepping back.
  private func panelClosed() {
    guard let panel else { return }
    panel.onClose = nil
    self.panel = nil
  }

  private func showMenu(from button: NSStatusBarButton) {
    let menu = NSMenu()
    menu.delegate = self
    if let note = hooksNote?() {
      let line = NSMenuItem(title: note, action: nil, keyEquivalent: "")
      line.isEnabled = false
      menu.addItem(line)
      menu.addItem(.separator())
    }
    menu.addItem(entry("Open window", #selector(openWindow(_:))))
    menu.addItem(entry("Connect", #selector(connect(_:))))
    menu.addItem(.separator())
    menu.addItem(entry("Turn off ctxscope", #selector(turnOff(_:))))
    menu.addItem(
      withTitle: "Quit ctxscope", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    item?.menu = menu
    button.performClick(nil)
  }

  /// A status item with a menu opens it on every click, so it is taken away
  /// again as soon as this one has closed.
  func menuDidClose(_ menu: NSMenu) {
    item?.menu = nil
  }

  private func entry(_ title: String, _ action: Selector) -> NSMenuItem {
    let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
    entry.target = self
    return entry
  }

  @objc private func openWindow(_ sender: NSMenuItem) {
    onOpenWindow?()
  }

  @objc private func connect(_ sender: NSMenuItem) {
    onConnect?()
  }

  @objc private func turnOff(_ sender: NSMenuItem) {
    onTurnOff?()
  }
}
