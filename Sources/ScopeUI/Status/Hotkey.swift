internal import Foundation

/// Registered by key code, not character, so the shortcut stays on the same
/// physical key on every layout.
public struct Hotkey: Sendable, Equatable {
  public struct Modifiers: OptionSet, Sendable, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    public static let command = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let control = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)
  }

  public let keyCode: UInt32
  public let modifiers: Modifiers
  public let label: String

  public init(keyCode: UInt32, modifiers: Modifiers, label: String) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.label = label
  }

  /// 8 is the C key. Control is added because option-command-C is taken by
  /// Chrome, Finder, Safari and VS Code, and a Carbon hotkey takes it from every app.
  public static let `default` = Hotkey(
    keyCode: 8, modifiers: [.command, .option, .control], label: "\u{2303}\u{2325}\u{2318}C")
}

@MainActor
public protocol HotkeyRegistrar: AnyObject {
  func register(_ hotkey: Hotkey, action: @escaping () -> Void) throws
  func unregister()
}
