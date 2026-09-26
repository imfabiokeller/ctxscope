import Foundation

/// The few things ctxscope's own settings are asked for.
///
/// A protocol so a test can hold them in memory. A test that makes a
/// `UserDefaults` suite leaves a file in the preferences folder of whoever
/// runs it, one per run.
protocol Settings: AnyObject {
  func string(forKey key: String) -> String?
  func bool(forKey key: String) -> Bool
  func set(_ value: Any?, forKey key: String)
  func removeObject(forKey key: String)
}

extension UserDefaults: Settings {}

/// Where ctxscope's own two settings live: the power state and the focused
/// session.
///
/// A diagnostic run gets a suite of its own. A check that launches the app to
/// see what the item does would otherwise write the fixture's session id into
/// the real focus and leave it there, and a temporary home does not help:
/// `CFFIXED_USER_HOME` does not redirect `UserDefaults`.
///
/// So a launch with a home of its own, which is what `scripts/demo.sh` makes,
/// gets a suite of its own too. It reads sessions from that home and focuses
/// one of them, and that focus must never replace the real one.
enum Defaults {
  /// The suite every diagnostic and scripted run writes to instead.
  static let diagnosticSuite = "dev.fabiokeller.ctxscope.diagnostic"
  /// The suite a launch under `CFFIXED_USER_HOME` writes to.
  static let fixedHomeSuite = "dev.fabiokeller.ctxscope.demo"
  /// The variable that gives a process a home other than the real one.
  static let fixedHomeVariable = "CFFIXED_USER_HOME"

  static func store(
    _ arguments: [String] = CommandLine.arguments,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> any Settings {
    if isDiagnostic(arguments) {
      return UserDefaults(suiteName: diagnosticSuite) ?? UserDefaults.standard
    }
    if hasFixedHome(environment) {
      return UserDefaults(suiteName: fixedHomeSuite) ?? UserDefaults.standard
    }
    return UserDefaults.standard
  }

  /// True when this launch is one of the checks rather than someone using
  /// the app.
  static func isDiagnostic(_ arguments: [String] = CommandLine.arguments) -> Bool {
    arguments.contains { $0.hasPrefix(Launch.diagnosticPrefix) }
  }

  /// True when this launch was given a home other than the real one.
  static func hasFixedHome(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Bool {
    environment[fixedHomeVariable].map { !$0.isEmpty } ?? false
  }
}
