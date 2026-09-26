import AppKit
import ScopeCore
import ScopeUI

/// The menu bar. Built here because the app has no scene to build it from,
/// and because there has to be a way to quit whatever else is on screen.
///
/// There is no theme picker: dark and light follow the system. Export lives
/// here rather than in the window.
@MainActor
enum AppMenu {
  static func install(export: @escaping (ExportFormat) -> Void, connect: @escaping () -> Void) {
    let main = NSMenu()
    main.addItem(appMenu(connect: connect))
    main.addItem(fileMenu(export: export))
    main.addItem(windowMenu())
    NSApp.mainMenu = main
  }

  private static func appMenu(connect: @escaping () -> Void) -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu()
    let target = ConnectTarget(connect: connect)
    let entry = NSMenuItem(
      title: "Connect", action: #selector(ConnectTarget.connect(_:)), keyEquivalent: "")
    entry.target = target
    connector = target
    menu.addItem(entry)
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Hide ctxscope", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit ctxscope", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    item.submenu = menu
    return item
  }

  /// Export, which used to be two buttons in the window's top bar.
  private static func fileMenu(export: @escaping (ExportFormat) -> Void) -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu(title: "File")
    let target = ExportTarget(export: export)
    for format in ExportFormat.allCases {
      let entry = NSMenuItem(
        title: "Export as \(format.rawValue.uppercased())",
        action: #selector(ExportTarget.export(_:)),
        keyEquivalent: format == .json ? "e" : "")
      entry.target = target
      entry.representedObject = format.rawValue
      menu.addItem(entry)
    }
    exporter = target
    item.submenu = menu
    return item
  }

  private static func windowMenu() -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu(title: "Window")
    menu.addItem(
      withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    menu.addItem(
      withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)),
      keyEquivalent: "m")
    item.submenu = menu
    NSApp.windowsMenu = menu
    return item
  }

  /// A menu item keeps an unowned target, so the one that answers has to be
  /// held for as long as the menu is.
  private static var exporter: ExportTarget?
  private static var connector: ConnectTarget?
}

/// What the Connect menu item does.
@MainActor
private final class ConnectTarget: NSObject {
  private let connected: () -> Void

  init(connect: @escaping () -> Void) {
    connected = connect
  }

  @objc func connect(_ sender: NSMenuItem) {
    connected()
  }
}

/// What an export menu item does.
@MainActor
private final class ExportTarget: NSObject {
  private let exported: (ExportFormat) -> Void

  init(export: @escaping (ExportFormat) -> Void) {
    exported = export
  }

  @objc func export(_ sender: NSMenuItem) {
    guard let raw = sender.representedObject as? String,
      let format = ExportFormat(rawValue: raw)
    else { return }
    exported(format)
  }
}
