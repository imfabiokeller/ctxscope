import Foundation
import Testing

@testable import ctxscope

/// Settings that live for the length of a test and nowhere else. A suite made
/// with `UserDefaults(suiteName:)` writes a file into the preferences folder
/// of whoever runs the tests, one per run.
final class MemorySettings: Settings {
  private var values: [String: Any] = [:]

  func string(forKey key: String) -> String? { values[key] as? String }
  func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
  func set(_ value: Any?, forKey key: String) { values[key] = value }
  func removeObject(forKey key: String) { values[key] = nil }
}

/// ctxscope's two settings belong to the person using it. A check that
/// launches the app would write a fixture's session id into the real focus and
/// leave it there, and a temporary home does not help: `CFFIXED_USER_HOME`
/// does not redirect `UserDefaults`.
@Suite("where the settings are kept")
struct DefaultsTests {
  @Test("a diagnostic run writes to a suite of its own")
  func diagnosticSuite() {
    #expect(Defaults.isDiagnostic(["/x/ctxscope", "--print-status"]))
    #expect(Defaults.isDiagnostic(["/x/ctxscope", "--print-hooks", "/tmp/x"]))
    #expect(Defaults.isDiagnostic(["/x/ctxscope", "--print-appearance"]))
    #expect(Defaults.store(["/x/ctxscope", "--print-status"]) !== UserDefaults.standard)
    #expect(Defaults.diagnosticSuite != UserDefaults.globalDomain)
  }

  @Test("an ordinary launch writes to the standard defaults")
  func standardSuite() {
    #expect(!Defaults.isDiagnostic(["/x/ctxscope"]))
    #expect(!Defaults.isDiagnostic(["/x/ctxscope", "--woken"]))
    #expect(!Defaults.isDiagnostic(["/x/ctxscope", "--window"]))
    #expect(Defaults.store(["/x/ctxscope"], environment: [:]) === UserDefaults.standard)
    #expect(
      Defaults.store(["/x/ctxscope"], environment: ["CFFIXED_USER_HOME": ""])
        === UserDefaults.standard)
  }

  /// The demo runs the app under a home of its own and focuses its session.
  /// That focus is the demo's, and must not replace the real one.
  @Test("a launch with a home of its own writes to a suite of its own")
  func fixedHomeSuite() {
    let environment = ["CFFIXED_USER_HOME": "/tmp/ctxscope-demo"]
    #expect(Defaults.hasFixedHome(environment))
    #expect(!Defaults.hasFixedHome([:]))
    #expect(Defaults.store(["/x/ctxscope"], environment: environment) !== UserDefaults.standard)
    #expect(Defaults.fixedHomeSuite != Defaults.diagnosticSuite)
    #expect(Defaults.fixedHomeSuite != UserDefaults.globalDomain)
  }

  /// The focus and the power state a run writes go where that run's settings
  /// are, and nowhere near the real ones.
  @Test("the two settings are whatever they are written into")
  func settingsAreSeparate() {
    let settings = MemorySettings()
    let focus = FocusStore(defaults: settings)
    let power = PowerStore(defaults: settings)
    let realFocus = UserDefaults.standard.string(forKey: FocusStore.key)

    focus.set("a-fixture-session")
    power.set(off: true)
    #expect(focus.session == "a-fixture-session")
    #expect(power.isOff)
    #expect(UserDefaults.standard.string(forKey: FocusStore.key) == realFocus)

    focus.set(nil)
    #expect(focus.session == nil)
  }
}

/// The focused session is remembered across launches, and it is the one thing
/// a scan is allowed to take back.
@Suite("the remembered focus")
struct FocusStoreTests {
  private let settings = MemorySettings()

  private func store() -> FocusStore {
    FocusStore(defaults: settings)
  }

  @Test("what was set comes back, and nothing set is nothing")
  func roundTrip() {
    let store = store()
    #expect(store.session == nil)
    store.set("a-session")
    #expect(store.session == "a-session")
    store.set(nil)
    #expect(store.session == nil)
  }

  @Test("it survives the process going away")
  func acrossLaunches() {
    FocusStore(defaults: settings).set("kept")
    // A second store over the same settings is what the next launch has.
    #expect(FocusStore(defaults: settings).session == "kept")
  }

  @Test("the key is ctxscope's own, beside the power state")
  func keys() {
    #expect(FocusStore.key == "focus.session")
    #expect(PowerStore.key == "power.isOff")
    #expect(FocusStore.key != PowerStore.key)
  }
}
