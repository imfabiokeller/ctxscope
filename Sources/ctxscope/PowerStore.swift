import Foundation
import ScopeConnect

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

// `open` passes arguments only when it launches the app; a running process gets the URL
// alone, so the woken flag marks a launch the hook caused.
enum LaunchReason {
  static func wasWoken(_ arguments: [String] = CommandLine.arguments) -> Bool {
    arguments.contains(HookWiring.wokenFlag)
  }
}

@MainActor
final class Power {
  private let store: PowerStore
  private(set) var isOff: Bool
  var onOff: (() -> Void)?
  var onOn: (() -> Void)?

  init(store: PowerStore, arguments: [String] = CommandLine.arguments) {
    self.store = store
    isOff = store.isOff && LaunchReason.wasWoken(arguments)
    // Only a hook launch keeps it off; any other launch turns it back on.
    if store.isOff != isOff { store.set(off: isOff) }
  }

  func off() {
    guard !isOff else { return }
    isOff = true
    store.set(off: true)
    onOff?()
  }

  func on() {
    guard isOff else { return }
    isOff = false
    store.set(off: false)
    onOn?()
  }
}
