import AppKit
import Carbon.HIToolbox
import ScopeUI

/// A global hotkey, claimed from the system.
///
/// Carbon's `RegisterEventHotKey` is the one way to take a key combination
/// system wide without the accessibility permission a global event monitor
/// needs. It claims one combination and gives it back, and that is all it
/// does: what to claim, and what it opens, is decided by the application.
@MainActor
final class CarbonHotkey: HotkeyRegistrar {
  enum Failure: Error, CustomStringConvertible {
    case refused(Int)

    var description: String {
      switch self {
      case .refused(let status): "the system refused the shortcut, error \(status)"
      }
    }
  }

  private var reference: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private var action: (() -> Void)?
  /// Every registration of this process, by id, so the one C callback can
  /// find the right action without a global.
  private static var actions: [UInt32: () -> Void] = [:]
  private static var nextID: UInt32 = 1

  private var id: UInt32 = 0

  func register(_ hotkey: Hotkey, action: @escaping () -> Void) throws {
    unregister()
    self.action = action
    id = Self.nextID
    Self.nextID += 1
    Self.actions[id] = action

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), Self.callback, 1, &eventType, nil, &handler)

    let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
    let status = RegisterEventHotKey(
      hotkey.keyCode, Self.carbonModifiers(hotkey.modifiers), hotKeyID,
      GetApplicationEventTarget(), 0, &reference)
    guard status == noErr else {
      Self.actions[id] = nil
      throw Failure.refused(Int(status))
    }
  }

  func unregister() {
    if let reference { UnregisterEventHotKey(reference) }
    reference = nil
    if let handler { RemoveEventHandler(handler) }
    handler = nil
    Self.actions[id] = nil
    action = nil
  }

  private static let signature: OSType = 0x4354_5853

  private static let callback: EventHandlerUPP = { _, event, _ in
    var pressed = EventHotKeyID()
    let status = GetEventParameter(
      event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
      MemoryLayout<EventHotKeyID>.size, nil, &pressed)
    guard status == noErr else { return status }
    let id = pressed.id
    Task { @MainActor in actions[id]?() }
    return noErr
  }

  static func carbonModifiers(_ modifiers: Hotkey.Modifiers) -> UInt32 {
    var value: UInt32 = 0
    if modifiers.contains(.command) { value |= UInt32(cmdKey) }
    if modifiers.contains(.option) { value |= UInt32(optionKey) }
    if modifiers.contains(.control) { value |= UInt32(controlKey) }
    if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
    return value
  }
}
