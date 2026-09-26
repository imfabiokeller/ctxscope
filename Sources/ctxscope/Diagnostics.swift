import Combine
import Foundation
import ScopeConnect
import ScopeCore
import ScopeUI

@MainActor
enum Diagnostics {
  static let appearanceFlag = "--print-appearance"
  static let statusFlag = "--print-status"
  // Takes an optional output file: an app launched by Launch Services, which URLs need,
  // has no readable standard error.
  static let hooksFlag = "--print-hooks"
  private static var changesSeen = 0

  static func runIfAsked() {
    if CommandLine.arguments.contains(appearanceFlag) { return printAppearance() }
  }

  // Prints event kinds and session ids only, never transcript text.
  static func printHooksIfAsked(_ hooks: HookListener, isOff: Bool) {
    guard CommandLine.arguments.contains(hooksFlag) else { return }
    guard let port = hooks.port else {
      say("hooks     no port could be bound")
      exit(1)
    }
    say("power     \(isOff ? "off" : "on")")
    say("hooks     listening on 127.0.0.1:\(port)")
    let previous = hooks.onEvent
    hooks.onEvent = { event in
      previous?(event)
      say("event     \(event.kind.rawValue) session \(event.sessionID)")
    }
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(30))
      exit(0)
    }
  }

  static func sayURL(_ url: URL, action: ScopeURL.Action?) {
    guard CommandLine.arguments.contains(hooksFlag) else { return }
    switch action {
    case .show(let session): say("url       show session \(session ?? "active")")
    case .wake: say("url       wake")
    case nil: say("url       ignored \(url)")
    }
  }

  static func printStatusIfAsked(
    _ status: StatusItemController, isWindowOpen: @escaping () -> Bool
  ) {
    guard CommandLine.arguments.contains(statusFlag) else { return }
    Task { @MainActor in
      // Long enough for the first session to have been read.
      try? await Task.sleep(for: .seconds(8))
      status.refresh()
      say("status    \(status.describe())")
      status.openPopoverForDiagnostic()
      try? await Task.sleep(for: .seconds(1))
      say("popover   open \(status.isPopoverShown)")
      status.openWindowForDiagnostic()
      try? await Task.sleep(for: .seconds(1))
      say("window    open \(isWindowOpen()), popover open \(status.isPopoverShown)")
      status.stop()
      say("off       \(status.describe())")
      exit(isWindowOpen() && !status.isShowing ? 0 : 1)
    }
  }

  private static func say(_ line: String) {
    let data = Data((line + "\n").utf8)
    guard let file = sink else { return FileHandle.standardError.write(data) }
    guard let handle = try? FileHandle(forWritingTo: file) else {
      try? data.write(to: file)
      return
    }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: data)
  }

  private static var sink: URL? {
    let arguments = CommandLine.arguments
    guard let slot = arguments.firstIndex(of: hooksFlag), slot + 1 < arguments.count,
      !arguments[slot + 1].hasPrefix("--")
    else { return nil }
    return URL(fileURLWithPath: arguments[slot + 1])
  }

  private static func printAppearance() {
    let themes = ThemeStore(appearance: Appearance.current())
    print("system \(Appearance.current().rawValue), theme \(themes.theme.name)")
    // The publisher does not promise an actor, so hop to the main actor.
    let token = Appearance.changes.sink { _ in
      Task { @MainActor in
        themes.follow(system: Appearance.current())
        print("changed to \(Appearance.current().rawValue), theme \(themes.theme.name)")
        changesSeen += 1
        if changesSeen >= 2 { exit(0) }
      }
    }
    // Long enough for a toggle and a toggle back.
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(30))
      exit(changesSeen > 0 ? 0 : 2)
    }
    RunLoop.main.run()
    _ = token
  }
}
