package import Foundation

/// One hook event, with the two fields ctxscope needs from it.
///
/// The payload shape is the one in the hooks reference: `session_id`,
/// `transcript_path`, `cwd` and `hook_event_name` on every event, `agent_id`
/// and `agent_type` inside a subagent, `reason` on `SessionEnd`. Only the
/// event name and the session id are read: ctxscope finds the transcript
/// itself, and a field nobody uses is a field that can go wrong. Everything
/// else is read past, so a transcript's text never enters ctxscope through a
/// hook.
package struct HookEvent: Sendable, Equatable {
  /// The one event ctxscope asks for. Everything else a session posts, from
  /// an older settings file or from somebody else's wiring, is answered with
  /// a 200 and dropped.
  package enum Kind: String, Sendable, Equatable, CaseIterable {
    case sessionEnd = "SessionEnd"
  }

  package let kind: Kind
  package let sessionID: String

  package init(kind: Kind, sessionID: String) {
    self.kind = kind
    self.sessionID = sessionID
  }

  /// The event in a hook's POST body, or nil when it is not one ctxscope
  /// listens for. An unknown event is not an error: the listener still answers
  /// 200, because a hook that is told something went wrong says so in the
  /// transcript for no reason.
  package static func decode(_ data: Data) -> HookEvent? {
    guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
      let name = payload.hookEventName, let kind = Kind(rawValue: name),
      let session = payload.sessionID, !session.isEmpty
    else { return nil }
    return HookEvent(kind: kind, sessionID: session)
  }

  private struct Payload: Decodable {
    let hookEventName: String?
    let sessionID: String?

    enum CodingKeys: String, CodingKey {
      case hookEventName = "hook_event_name"
      case sessionID = "session_id"
    }
  }
}

/// What the listener answers, decided before anything is done about it.
///
/// Claude Code posts from a process on this machine with no `Origin` and with
/// the host it was given. A page in a browser cannot set either, so refusing a
/// request that carries an `Origin`, or that names a host ctxscope never
/// published, keeps a page somebody opened from posting made-up events at it.
package enum HookRouter {
  package static func status(for request: HookRequest, port: UInt16?) -> HTTPStatus {
    guard request.path == HookWiring.path else { return .notFound }
    guard request.method == "POST" else { return .methodNotAllowed }
    guard request.headers["origin"] == nil else { return .forbidden }
    guard isOurs(host: request.headers["host"], port: port) else { return .forbidden }
    return .ok
  }

  /// The hook URL names 127.0.0.1 and our port. `localhost` is the same
  /// machine by another name and is taken too; anything else is not us.
  static func isOurs(host: String?, port: UInt16?) -> Bool {
    guard let host else { return false }
    guard let port else { return true }
    let names = ["\(HookWiring.host):\(port)", "localhost:\(port)"]
    return names.contains(host.lowercased())
  }
}
