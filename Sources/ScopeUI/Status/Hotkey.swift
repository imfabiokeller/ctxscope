internal import Foundation

/// A global key combination, as data.
///
/// The key code is the system's, because a global hotkey is registered by code
/// and not by character: the same physical key is a different character on
/// another layout, and the shortcut has to stay where the fingers are.
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
  /// What to show in a menu. The one place the shortcut is spelled out.
  public let label: String

  public init(keyCode: UInt32, modifiers: Modifiers, label: String) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.label = label
  }

  /// Control-option-command-C. 8 is the C key.
  ///
  /// A Carbon hotkey takes the combination from every app on the machine, so
  /// the default has to be one nobody else uses. Option-command-C is Chrome's
  /// inspect element, Finder's copy as pathname, Safari's console and VS
  /// Code's match case. Adding control takes it out of all four.
  public static let `default` = Hotkey(
    keyCode: 8, modifiers: [.command, .option, .control], label: "\u{2303}\u{2325}\u{2318}C")
}

/// Whatever can claim a key combination from the whole system.
///
/// A protocol because the thing that does it is Carbon, which needs a running
/// application, and because what is claimed, and what happens when the system
/// refuses, are checked against a registrar that only pretends to.
@MainActor
public protocol HotkeyRegistrar: AnyObject {
  func register(_ hotkey: Hotkey, action: @escaping () -> Void) throws
  func unregister()
}
