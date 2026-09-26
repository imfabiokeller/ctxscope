package import Foundation

/// The `ctxscope://` scheme, which is how a chat reaches ctxscope.
///
/// `ctxscope://show?session=<id>` focuses that session and opens the window on
/// it, which is what `/ctxscope` typed in a chat does. `ctxscope://show` with
/// no id is a substitution that failed, and takes the session written to most
/// recently, once. `ctxscope://wake` starts ctxscope if it is not running and
/// opens nothing.
package enum ScopeURL {
  package static let scheme = "ctxscope"

  package enum Action: Sendable, Equatable {
    case show(session: String?)
    /// Be there. No window, no focus, and an off ctxscope stays off.
    case wake
  }

  package static func parse(_ url: URL) -> Action? {
    guard url.scheme?.lowercased() == scheme else { return nil }
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    // `ctxscope://show` puts the verb in the host, `ctxscope:show` in the path.
    let verb = parts.host ?? parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    switch verb.lowercased() {
    case "wake": return .wake
    case "show":
      let session = parts.queryItems?.first { $0.name == "session" }?.value
      // The same rule `show(session:)` writes a URL by. An id that is not one
      // is what an unsubstituted placeholder looks like, and the answer to
      // that is the session written to most recently, not a focus on a
      // session nothing could have.
      return .show(session: session.flatMap(valid))
    default: return nil
    }
  }

  /// What Claude Code writes the session id in place of before the shell sees
  /// the command. It is not a value yet, so it is not escaped like one.
  package static let sessionPlaceholder = "${CLAUDE_SESSION_ID}"

  /// The URL the skill opens, and the one a link elsewhere would use.
  ///
  /// A session id is plain. Anything else is not one, and rather than build a
  /// URL out of it this falls back to no id at all, which the other side
  /// answers with the session written to most recently.
  package static func show(session: String? = nil) -> String {
    guard let session, session == sessionPlaceholder || valid(session) != nil else {
      return "\(scheme)://show"
    }
    return "\(scheme)://show?session=\(session)"
  }

  /// A session id, or nil when the text is not one. A session id is plain:
  /// letters, digits, hyphens and underscores, and nothing else.
  package static func valid(_ session: String) -> String? {
    guard !session.isEmpty, session.count <= maximumIDLength,
      session.allSatisfy(isPlain)
    else { return nil }
    return session
  }

  /// Longer than a UUID and shorter than anything worth reading twice.
  private static let maximumIDLength = 64

  /// The URL the `SessionStart` hook opens. It starts ctxscope when nothing
  /// is running and does nothing else.
  package static var wake: String { "\(scheme)://wake" }

  private static func isPlain(_ character: Character) -> Bool {
    character.isASCII
      && (character.isLetter || character.isNumber || character == "-"
        || character == "_")
  }
}
