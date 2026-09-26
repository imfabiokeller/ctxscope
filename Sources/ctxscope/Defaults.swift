import Foundation

// A protocol so tests stay in memory: a `UserDefaults` suite leaves a file in the real
// preferences folder.
protocol Settings: AnyObject {
  func string(forKey key: String) -> String?
  func bool(forKey key: String) -> Bool
  func set(_ value: Any?, forKey key: String)
  func removeObject(forKey key: String)
}

extension UserDefaults: Settings {}

// Diagnostic and fixed-home launches get their own suite so they never overwrite the real
// focus: `UserDefaults` does not follow `CFFIXED_USER_HOME`.
enum Defaults {
  static let diagnosticSuite = "dev.fabiokeller.ctxscope.diagnostic"
  static let fixedHomeSuite = "dev.fabiokeller.ctxscope.demo"
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

  static func isDiagnostic(_ arguments: [String] = CommandLine.arguments) -> Bool {
    arguments.contains { $0.hasPrefix(Launch.diagnosticPrefix) }
  }

  static func hasFixedHome(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Bool {
    environment[fixedHomeVariable].map { !$0.isEmpty } ?? false
  }
}
