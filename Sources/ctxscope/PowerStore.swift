import Foundation
import ScopeConnect

/// Where the off state is kept between launches.
///
/// It is a setting of ctxscope's and not of Claude's: the settings file is
/// written once, when Connect is clicked, and turning the instrument off and
/// on again never touches it again. So off has to survive a quit, and a
/// session starting must not undo it.
struct PowerStore {
  static let key = "power.isOff"
  let defaults: any Settings

  init(defaults: any Settings) {
    self.defaults = defaults
  }

  var isOff: Bool { defaults.bool(forKey: Self.key) }

  func set(off: Bool) {
    defaults.set(off, forKey: Self.key)
  }
}

/// Why this process is running.
///
/// A launch the `SessionStart` hook caused is not a person asking for
/// anything, so it leaves an off ctxscope off. A launch from Finder, Spotlight
/// or the Dock is a person asking, so it turns it back on. The two are told
/// apart by the flag the hook's command passes, which `open` hands to the
/// application only when it actually launches it: a process that was already
/// running gets the URL and no arguments at all.
enum LaunchReason {
  /// The flag the hook's command passes, which is written into the settings
  /// file as part of that command and so lives with it.
  static func wasWoken(_ arguments: [String] = CommandLine.arguments) -> Bool {
    arguments.contains(HookWiring.wokenFlag)
  }
}

/// Whether ctxscope is following anything, and what changes that.
///
/// Off means the menu bar item is gone, nothing is read and nothing is followed. The
/// listener answers either way, so a connected Claude session sees the same
/// 200 whatever this says.
///
/// Only a person turns it back on: opening the app, or `/ctxscope` in a chat.
/// A session starting never does, because a session starting is not somebody
/// asking for the instrument.
@MainActor
final class Power {
  private let store: PowerStore
  private(set) var isOff: Bool
  /// Told when the instrument has to stop and when it may start again.
  var onOff: (() -> Void)?
  var onOn: (() -> Void)?

  init(store: PowerStore, arguments: [String] = CommandLine.arguments) {
    self.store = store
    isOff = store.isOff && LaunchReason.wasWoken(arguments)
    // A launch someone asked for is someone asking for it back.
    if store.isOff != isOff { store.set(off: isOff) }
  }

  /// The power control in the popover.
  func off() {
    guard !isOff else { return }
    isOff = true
    store.set(off: true)
    onOff?()
  }

  /// Someone opening the app, or `/ctxscope` in a chat.
  func on() {
    guard isOff else { return }
    isOff = false
    store.set(off: false)
    onOn?()
  }
}
