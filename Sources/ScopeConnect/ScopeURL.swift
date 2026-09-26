package import Foundation

package enum ScopeURL {
  package static let scheme = "ctxscope"

  package enum Action: Sendable, Equatable {
    case show(session: String?)
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
      return .show(session: session.flatMap(valid))
    default: return nil
    }
  }

  // Claude Code substitutes this before the shell runs, so it is not escaped.
  package static let sessionPlaceholder = "${CLAUDE_SESSION_ID}"

  package static func show(session: String? = nil) -> String {
    guard let session, session == sessionPlaceholder || valid(session) != nil else {
      return "\(scheme)://show"
    }
    return "\(scheme)://show?session=\(session)"
  }

  package static func valid(_ session: String) -> String? {
    guard !session.isEmpty, session.count <= maximumIDLength,
      session.allSatisfy(isPlain)
    else { return nil }
    return session
  }

  // Longer than a UUID.
  private static let maximumIDLength = 64

  package static var wake: String { "\(scheme)://wake" }

  private static func isPlain(_ character: Character) -> Bool {
    character.isASCII
      && (character.isLetter || character.isNumber || character == "-"
        || character == "_")
  }
}
