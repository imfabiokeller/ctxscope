import AppKit
import ScopeCore
import ScopeUI
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
  private let model: InstrumentModel
  private let themes: ThemeStore
  private var item: NSStatusItem?
  private var panel: StatusPanel?
  private var shown: StatusReading??
  private var drawn: StatusFace?

  var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  var onOpenWindow: (() -> Void)?
  var onConnect: (() -> Void)?
  var onTurnOff: (() -> Void)?
  var hooksNote: (() -> String?)?

  init(model: InstrumentModel, themes: ThemeStore) {
    self.model = model
    self.themes = themes
    super.init()
  }

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

  func stop() {
    closePanel()
    if let item { NSStatusBar.system.removeStatusItem(item) }
    item = nil
    shown = nil
    drawn = nil
  }

  var isShowing: Bool { item != nil }
  var isPopoverShown: Bool { panel?.isShown == true }

  // Never the menu: an open menu blocks the diagnostic waiting for a click.
  func openPopoverForDiagnostic() {
    guard let button = item?.button else { return }
    togglePanel(from: button)
  }

  func openWindowForDiagnostic() {
    closePanel()
    onOpenWindow?()
  }

  func describe() -> String {
    guard let button = item?.button else { return "status item absent" }
    guard let image = button.image else { return "status item with no image" }
    let number = button.attributedTitle.string.isEmpty ? "no number" : button.attributedTitle.string
    let size = "\(Int(image.size.width))x\(Int(image.size.height))"
    let kind = image.isTemplate ? "template" : "colored"
    return "status item \(size) \(kind), \(number), length \(Int(button.frame.width))"
  }

  func refresh() {
    guard let button = item?.button else { return }
    refresh(on: button)
  }

  func refresh(on button: any StatusButton) {
    let reading = StatusReading.make(from: model)
    guard shown != .some(reading) else { return }
    shown = .some(reading)
    let face = StatusFace(reading: reading)
    // Added before `draw`: the transition animates the next drawing.
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
      tooltip: StatusVoice.tooltip(reading),
      value: StatusVoice.value(reading))
  }

  @objc private func clicked(_ sender: NSStatusBarButton) {
    let event = NSApp.currentEvent
    let secondary =
      event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
    if secondary { return showMenu(from: sender) }
    togglePanel(from: sender)
  }

  private func togglePanel(from button: NSStatusBarButton) {
    if isPopoverShown { return closePanel() }
    guard let bar = button.window else { return }
    model.reloadSessions()
    let panel = StatusPanel(content: popover, theme: themes.theme)
    panel.onClose = { [weak self] in self?.panelClosed() }
    self.panel = panel
    panel.show(under: bar)
  }

  private var popover: some View {
    StatusPopoverHost(
      model: model, themes: themes, home: NSHomeDirectory(),
      actions: PopoverActions(
        // Window first, so the closing panel leaves it in front.
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
    if panel != nil { panelClosed() }
  }

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

  // A status item with a menu opens it on every click, so it is removed after each.
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
