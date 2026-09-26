import AppKit
import Combine
import ScopeConnect
import ScopeCore
import ScopeUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let model = InstrumentModel(feed: TranscriptFeed())
  private let themes = ThemeStore()
  private lazy var status = StatusItemController(model: model, themes: themes)
  private var window: InstrumentWindowController?
  private var appearanceToken: (any Cancellable)?
  private let hooks = HookListener()
  private var connect: ConnectWindowController?
  private let power = Power(store: PowerStore(defaults: Defaults.store()))
  private let focus = FocusStore(defaults: Defaults.store())
  private let shortcut: any HotkeyRegistrar = CarbonHotkey()

  func applicationDidFinishLaunching(_ notification: Notification) {
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

  private func hotkey() {
    do {
      try shortcut.register(.default) { [weak self] in self?.showWindow() }
    } catch {
      FileHandle.standardError.write(
        Data("ctxscope: the system refused \(Hotkey.default.label): \(error)\n".utf8))
    }
  }

  private func startHooks() {
    hooks.onEvent = { [weak self] event in self?.model.apply(event) }
    let wanted = (try? ConnectService(home: .real()).status())?.port
    Task { @MainActor in
      await hooks.start(preferring: wanted)
      Diagnostics.printHooksIfAsked(hooks, isOff: power.isOff)
    }
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      let action = ScopeURL.parse(url)
      Diagnostics.sayURL(url, action: action)
      guard let action else { continue }
      switch action {
      // Wake only brings the process up; an off ctxscope stays off.
      case .wake: break
      case .show:
        // On first: a stopped model reads nothing.
        turnOn()
        model.open(action)
        showWindow()
      }
    }
  }

  private func hooksNote() -> String? {
    let status = try? ConnectService(home: .real()).status()
    guard status?.needsReconnect(listening: hooks.port) == true else { return nil }
    return "Hooks: reconnect needed"
  }

  private func turnOff() {
    power.off()
  }

  private func turnOn() {
    power.on()
  }

  private func turnedOff() {
    status.stop()
    model.stop()
  }

  private func turnedOn() {
    model.start()
    status.start()
    status.refresh()
  }

  func showConnect() {
    if connect == nil {
      let controller = ConnectWindowController(
        home: .real(), listening: hooks.port, themes: themes)
      controller.onClose = { [weak self] in self?.connect = nil }
      connect = controller
    }
    connect?.show(listening: hooks.port)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows: Bool
  ) -> Bool {
    showWindow()
    return true
  }

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

  private func export(_ format: ExportFormat) {
    guard let data = model.export(format) else { return }
    InstrumentWindowController.save(data, name: model.exportName(format))
  }

  private func windowClosed() {
    window = nil
    NSApp.setActivationPolicy(.accessory)
  }
}
