import ScopeUI

@MainActor
enum Launch {
  // Off must stop the model explicitly: it follows events from creation, even without
  // `start()`.
  static func begin(model: InstrumentModel, focus: String?, isOff: Bool) {
    model.focus(session: focus)
    if isOff {
      model.stop()
    } else {
      model.start()
    }
  }

  static func opensWindow(_ arguments: [String] = CommandLine.arguments) -> Bool {
    if arguments.contains(windowFlag) { return true }
    guard !LaunchReason.wasWoken(arguments) else { return false }
    return !arguments.contains { $0.hasPrefix(diagnosticPrefix) }
  }

  nonisolated static let windowFlag = "--window"
  nonisolated static let diagnosticPrefix = "--print-"
}
