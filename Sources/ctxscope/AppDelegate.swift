import AppKit
import Combine
import ScopeConnect
import ScopeCore
import ScopeUI

/// The composition root: it builds the feed, the model, the theme store and
/// the menu bar item, and hands them to the window when one is asked for. Every
/// decision it could make has already been made in a module that can be
/// tested.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let model = InstrumentModel(feed: TranscriptFeed())
  private let themes = ThemeStore()
  private lazy var status = StatusItemController(model: model, themes: themes)
  private var window: InstrumentWindowController?
  private var appearanceToken: (any Cancellable)?
  /// The listener the hooks post to. It binds a port whether or not anything is
  /// connected: a listener nobody posts to costs one socket and no work.
  private let hooks = HookListener()
  private var connect: ConnectWindowController?
  /// Whether ctxscope is on, kept between launches: Claude's settings file is
  /// written once, and everything after that is ctxscope's own business. The listener stays up either way, so hooks that are
  /// connected still get their 200.
  private let power = Power(store: PowerStore(defaults: Defaults.store()))
  /// The session ctxscope shows, remembered across launches.
  private let focus = FocusStore(defaults: Defaults.store())
  /// The global shortcut, which opens the window.
  private let shortcut: any HotkeyRegistrar = CarbonHotkey()

  func applicationDidFinishLaunching(_ notification: Notification) {
    // An accessory: no Dock icon and no menu bar of its own while the status
    // item is all there is. The window brings both back while it is open.
    NSApp.setActivationPolicy(.accessory)
    themes.follow(system: Appearance.current())
    appearanceToken = Appearance.changes.sink { _ in
      Task { @MainActor in self.themes.follow(system: Appearance.current()) }
    }
    AppMenu.install(
      export: { [weak self] format in self?.export(format) },
      connect: { [weak self] in self?.showConnect() })
    power.onOff = { [weak self] in self?.turnedOff() }
    power.onOn = { [weak self] in self?.turnedOn() }
    model.onFocusChanged = { [weak self] session in self?.focus.set(session) }
    // What was being shown when ctxscope was last up. The scan decides
    // whether this machine still has it.
    Launch.begin(model: model, focus: focus.session, isOff: power.isOff)
    startHooks()
    status.onOpenWindow = { [weak self] in self?.showWindow() }
    status.onConnect = { [weak self] in self?.showConnect() }
    status.onTurnOff = { [weak self] in self?.turnOff() }
    status.hooksNote = { [weak self] in self?.hooksNote() }
    if !power.isOff { status.start() }
    watchModel()
    hotkey()
    if Launch.opensWindow() { showWindow() }
    Diagnostics.printStatusIfAsked(status) { [weak self] in self?.window?.isVisible == true }
  }

  func applicationWillTerminate(_ notification: Notification) {
    status.stop()
    model.stop()
    hooks.stop()
    shortcut.unregister()
  }

  /// The menu bar item follows what the window would show. Observation calls
  /// this once per change and never in between.
  private func watchModel() {
    withObservationTracking {
      _ = model.analysis
      _ = model.liveness.isLive
    } onChange: {
      Task { @MainActor [weak self] in
        self?.status.refresh()
        self?.watchModel()
      }
    }
  }

  /// One shortcut, claimed at launch. A refusal is said out loud rather than
  /// leaving a shortcut that quietly does nothing.
  private func hotkey() {
    do {
      try shortcut.register(.default) { [weak self] in self?.showWindow() }
    } catch {
      FileHandle.standardError.write(
        Data("ctxscope: the system refused \(Hotkey.default.label): \(error)\n".utf8))
    }
  }

  /// Takes the port the settings file already names, so hooks that are already
  /// written keep working across a restart. Reading it is all that happens
  /// without anybody asking for anything.
  private func startHooks() {
    hooks.onEvent = { [weak self] event in self?.model.apply(event) }
    let wanted = (try? ConnectService(home: .real()).status())?.port
    Task { @MainActor in
      await hooks.start(preferring: wanted)
      Diagnostics.printHooksIfAsked(hooks, isOff: power.isOff)
    }
  }

  /// A `ctxscope://` URL, which is what `/ctxscope` in a chat opens.
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      let action = ScopeURL.parse(url)
      Diagnostics.sayURL(url, action: action)
      guard let action else { continue }
      switch action {
      // A session started, so be there and nothing more. Being up is the
      // whole point: an off ctxscope stays off, shows nothing, reads nothing,
      // and its listener goes on answering.
      case .wake: break
      case .show:
        // On first, because a stopped model reads nothing: /ctxscope is
        // someone asking for the instrument back.
        turnOn()
        model.open(action)
        showWindow()
      }
    }
  }

  /// One line for the menu bar item's menu when the hooks in the settings file would
  /// not reach this ctxscope: a stored port that was taken, or a half written
  /// file. Nobody would notice until they opened the panel. Read every time
  /// the menu opens, so it goes away once Connect has been clicked again.
  private func hooksNote() -> String? {
    let status = try? ConnectService(home: .real()).status()
    guard status?.needsReconnect(listening: hooks.port) == true else { return nil }
    return "Hooks: reconnect needed"
  }

  /// The power control in the popover.
  ///
  /// It used to quit. With hooks connected that leaves every prompt posting
  /// at nothing, and the hooks reference says a failed hook shows a notice in
  /// the transcript. So turning ctxscope off takes the menu bar item away and
  /// the model reads nothing, while the listener stays up: one socket, no
  /// window, no work, and nothing for Claude to report. Opening the app again
  /// brings it back. Quit, in the menu, is what ends the process.
  private func turnOff() {
    power.off()
  }

  /// Only a person does this: opening the app, or `/ctxscope` in a chat. A
  /// session starting never does.
  private func turnOn() {
    power.on()
  }

  /// What the power control being switched off does: the item goes and the
  /// model reads nothing. The listener stays up.
  private func turnedOff() {
    status.stop()
    model.stop()
  }

  /// And back on again.
  private func turnedOn() {
    model.start()
    status.start()
    status.refresh()
  }

  /// The Connect panel, from the app menu and from the menu bar item's menu.
  func showConnect() {
    if connect == nil {
      let controller = ConnectWindowController(
        home: .real(), listening: hooks.port, themes: themes)
      controller.onClose = { [weak self] in self?.connect = nil }
      connect = controller
    }
    connect?.show(listening: hooks.port)
  }

  /// Closing the last window leaves the menu bar item, which is the app.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  /// Opening the app again while only the menu bar item is up opens the window.
  /// Without this there was no way back in but the shortcut.
  func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows: Bool
  ) -> Bool {
    showWindow()
    return true
  }

  /// Opens the instrument window, or brings back the one that is already
  /// open. The app becomes a normal one for as long as it is up, so it has a
  /// menu bar and a place in the Dock while there is a window to go with it.
  func showWindow() {
    turnOn()
    if let window {
      NSApp.setActivationPolicy(.regular)
      window.show()
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let controller = InstrumentWindowController(model: model, themes: themes)
    controller.onClose = { [weak self] in self?.windowClosed() }
    window = controller
    NSApp.setActivationPolicy(.regular)
    controller.show()
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Exports what the window is showing, from the File menu. A save panel
  /// belongs to the app, and an error it hits is said out loud rather than
  /// swallowed.
  private func export(_ format: ExportFormat) {
    guard let data = model.export(format) else { return }
    InstrumentWindowController.save(data, name: model.exportName(format))
  }

  private func windowClosed() {
    window = nil
    NSApp.setActivationPolicy(.accessory)
  }
}
