import Foundation
import ScopeConnect
import Testing

@testable import ctxscope

@Suite("the power control")
@MainActor
struct PowerTests {
  private let settings = MemorySettings()

  private func store() -> PowerStore {
    PowerStore(defaults: settings)
  }

  private let woken = ["/x/ctxscope", HookWiring.wokenFlag]
  private let byHand = ["/x/ctxscope"]

  @Test("off survives a quit")
  func offIsKept() {
    let store = store()
    let first = Power(store: store, arguments: byHand)
    #expect(!first.isOff)
    first.off()
    #expect(store.isOff)

    let second = Power(store: store, arguments: woken)
    #expect(second.isOff)
    #expect(store.isOff)
  }

  @Test("a session starting never turns it back on")
  func wakeWhileOff() {
    let store = store()
    store.set(off: true)
    let power = Power(store: store, arguments: woken)
    #expect(power.isOff)
    #expect(power.isOff)
    #expect(store.isOff)
  }

  @Test("a session starting leaves an on ctxscope on")
  func wakeWhileOn() {
    let store = store()
    let power = Power(store: store, arguments: woken)
    #expect(!power.isOff)
    #expect(!store.isOff)
  }

  @Test("opening the app turns it back on")
  func openWhileOff() {
    let store = store()
    store.set(off: true)
    let launched = Power(store: store, arguments: byHand)
    #expect(!launched.isOff)
    #expect(!store.isOff)

    store.set(off: true)
    let running = Power(store: store, arguments: woken)
    #expect(running.isOff)
    var started = 0
    running.onOn = { started += 1 }
    running.on()
    #expect(!running.isOff)
    #expect(!store.isOff)
    #expect(started == 1)
  }

  @Test("/ctxscope turns it on, which is the same door")
  func showWhileOff() {
    let store = store()
    store.set(off: true)
    let power = Power(store: store, arguments: woken)
    #expect(power.isOff)
    #expect(ScopeURL.parse(URL(string: ScopeURL.wake)!) == .wake)
    #expect(ScopeURL.parse(URL(string: "ctxscope://show")!) == .show(session: nil))
    power.on()
    #expect(!power.isOff)
  }

  @Test("turning it off and on again tells whoever is listening, once")
  func transitions() {
    let power = Power(store: store(), arguments: byHand)
    var stopped = 0
    var started = 0
    power.onOff = { stopped += 1 }
    power.onOn = { started += 1 }
    power.on()
    #expect(started == 0, "it was already on")
    power.off()
    power.off()
    #expect(stopped == 1)
    power.on()
    power.on()
    #expect(started == 1)
  }

  @Test("the flag the hook passes is the one the settings file carries")
  func flag() {
    #expect(HookWiring.wakeCommand.contains(HookWiring.wokenFlag))
    #expect(HookWiring.wakeCommand.contains("--args"))
    #expect(LaunchReason.wasWoken(woken))
    #expect(!LaunchReason.wasWoken(byHand))
  }
}
