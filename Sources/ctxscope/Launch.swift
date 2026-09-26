import ScopeUI

/// What a launch does to the instrument, in one place so it can be checked
/// without an application around it.
@MainActor
enum Launch {
  /// The session that was focused when ctxscope was last up, and then on or
  /// off.
  ///
  /// Off has to be said out loud. A model follows from the moment it exists,
  /// so a launch that merely skipped `start()` left every hook event going
  /// through it: one prompt from the focused session and the transcript was
  /// read, the session marked live and the requests counted, all while
  /// ctxscope was turned off.
  static func begin(model: InstrumentModel, focus: String?, isOff: Bool) {
    model.focus(session: focus)
    if isOff {
      model.stop()
    } else {
      model.start()
    }
  }

  /// Whether this launch opens the window.
  ///
  /// A launch from Finder, Spotlight or the Dock is someone asking for the
  /// instrument, and an icon in the bar alone is easy to miss, or hidden
  /// behind the notch. A launch a session caused opens
  /// nothing, and neither does a diagnostic run, which says what it found and
  /// quits.
  static func opensWindow(_ arguments: [String] = CommandLine.arguments) -> Bool {
    if arguments.contains(windowFlag) { return true }
    guard !LaunchReason.wasWoken(arguments) else { return false }
    return !arguments.contains { $0.hasPrefix(diagnosticPrefix) }
  }

  /// Asks for the window whatever else this launch is.
  nonisolated static let windowFlag = "--window"
  /// Every diagnostic flag starts with this.
  nonisolated static let diagnosticPrefix = "--print-"
}
