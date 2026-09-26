import AppKit
import Carbon.HIToolbox
import Foundation
import ScopeUI
import Testing

@testable import ctxscope

/// Fake registrar, so the test never takes a key combination from the whole machine.
@MainActor
private final class FakeRegistrar: HotkeyRegistrar {
  struct Refused: Error {}
  var refuses = false
  private(set) var registered: Hotkey?
  private(set) var unregistered = 0
  private var action: (() -> Void)?

  func register(_ hotkey: Hotkey, action: @escaping () -> Void) throws {
    if refuses { throw Refused() }
    registered = hotkey
    self.action = action
  }

  func unregister() {
    unregistered += 1
    registered = nil
    action = nil
  }

  func press() { action?() }
}

@Suite("the shortcut")
@MainActor
struct HotkeyTests {
  @Test("the default is control-option-command-C")
  func theDefault() {
    let hotkey = Hotkey.default
    #expect(hotkey.keyCode == 8)
    #expect(hotkey.modifiers == [.command, .option, .control])
    #expect(hotkey.label == "\u{2303}\u{2325}\u{2318}C")
    // Option-command-C alone is taken by four other applications.
    #expect(hotkey.modifiers.contains(.control))
  }

  @Test("the modifiers are the ones Carbon wants")
  func carbonModifiers() {
    #expect(CarbonHotkey.carbonModifiers([]) == 0)
    #expect(CarbonHotkey.carbonModifiers([.command]) == UInt32(cmdKey))
    #expect(CarbonHotkey.carbonModifiers([.option]) == UInt32(optionKey))
    #expect(CarbonHotkey.carbonModifiers([.control]) == UInt32(controlKey))
    #expect(CarbonHotkey.carbonModifiers([.shift]) == UInt32(shiftKey))
    #expect(
      CarbonHotkey.carbonModifiers(Hotkey.default.modifiers)
        == UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey))
  }

  @Test("what is claimed is the default, and it opens the window")
  func registers() throws {
    let registrar = FakeRegistrar()
    var opened = 0
    try registrar.register(.default) { opened += 1 }
    #expect(registrar.registered == Hotkey.default)

    registrar.press()
    #expect(opened == 1)
    registrar.press()
    #expect(opened == 2)
  }

  @Test("a refusal is thrown rather than leaving a shortcut that does nothing")
  func refusal() {
    let registrar = FakeRegistrar()
    registrar.refuses = true
    #expect(throws: FakeRegistrar.Refused.self) {
      try registrar.register(.default) {}
    }
    #expect(registrar.registered == nil)
  }

  @Test("giving it back leaves nothing behind")
  func unregisters() throws {
    let registrar = FakeRegistrar()
    var opened = 0
    try registrar.register(.default) { opened += 1 }
    registrar.unregister()
    registrar.press()
    #expect(opened == 0)
    #expect(registrar.unregistered == 1)
  }

  @Test("the real registrar says what the system refused")
  func refusalMessage() {
    let failure = CarbonHotkey.Failure.refused(-9878)
    #expect(failure.description.contains("-9878"))
    #expect(failure.description.contains("refused"))
  }
}
