import Combine
import Foundation
import ScopeConnect
import ScopeCore
import ScopeUI

/// The checks a bundled build answers without anybody granting screen capture
/// or looking at a picture.
///
/// Every one of them writes to standard error and quits, and every one runs
/// against ctxscope's diagnostic defaults rather than the real ones.
@MainActor
enum Diagnostics {
  /// `ctxscope --print-appearance` says what the app thinks the system is
  /// showing and which theme it would pick, and then waits for one change and
  /// says it again. It is how following the system is checked without anybody
  /// looking at a screen.
  static let appearanceFlag = "--print-appearance"
  /// `ctxscope --print-status` launches normally and then says what the menu
  /// bar item did. It is handled by the delegate, because it needs a running
  /// application, and named here with the others.
  static let statusFlag = "--print-status"
  /// `ctxscope --print-hooks [FILE]` says which port the listener took and
  /// then prints a line for everything that reaches the app from a Claude
  /// session: hook events, and the `ctxscope://` URLs the skill opens. Thirty
  /// seconds, and no settings file is touched. It is how level 1 is shown to
  /// work end to end from a script.
  ///
  /// The file is what makes the URL half of that checkable. A `ctxscope://`
  /// URL is delivered by Launch Services to the app it launched itself, so the
  /// check has to launch it the same way, and an app launched that way has no
  /// standard error anybody can read.
  static let hooksFlag = "--print-hooks"
  /// How many system switches have been seen. On the main actor with the rest
  /// of this, so the notification callback hands its work here rather than
  /// asserting it is already there.
  private static var changesSeen = 0

  static func runIfAsked() {
    if CommandLine.arguments.contains(appearanceFlag) { return printAppearance() }
  }

  /// Prints the port and then every event, for as long as a script needs.
  /// The events it prints are the kind and the session, never anything a
  /// transcript said.
  static func printHooksIfAsked(_ hooks: HookListener, isOff: Bool) {
    guard CommandLine.arguments.contains(hooksFlag) else { return }
    guard let port = hooks.port else {
      say("hooks     no port could be bound")
      exit(1)
    }
    // Whether this launch is following anything. A session that woke ctxscope
    // while it was turned off leaves it off.
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

  /// One line per `ctxscope://` URL the app is handed, under the same flag.
  static func sayURL(_ url: URL, action: ScopeURL.Action?) {
    guard CommandLine.arguments.contains(hooksFlag) else { return }
    switch action {
    case .show(let session): say("url       show session \(session ?? "active")")
    case .wake: say("url       wake")
    case nil: say("url       ignored \(url)")
    }
  }

  /// `ctxscope --print-status` says what the menu bar item is, opens its
  /// popover, opens the window from it, and quits. It is how a bundled launch
  /// is checked without screen capture.
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

  /// Straight out, unbuffered, so a line that has been printed is a line that
  /// has been seen whatever happens next. To standard error, or to the file
  /// `--print-hooks` named.
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

  /// The file `--print-hooks` named, if it named one.
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
    // The publisher says nothing about which actor it delivers on, so the work
    // is handed to the main actor rather than asserted to be on it.
    let token = Appearance.changes.sink { _ in
      Task { @MainActor in
        themes.follow(system: Appearance.current())
        print("changed to \(Appearance.current().rawValue), theme \(themes.theme.name)")
        changesSeen += 1
        if changesSeen >= 2 { exit(0) }
      }
    }
    // Long enough for a toggle and a toggle back, never longer.
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(30))
      exit(changesSeen > 0 ? 0 : 2)
    }
    RunLoop.main.run()
    _ = token
  }
}
