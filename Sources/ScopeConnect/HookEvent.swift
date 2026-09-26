package import Foundation

package struct HookEvent: Sendable, Equatable {
  package enum Kind: String, Sendable, Equatable, CaseIterable {
    case sessionEnd = "SessionEnd"
  }

  package let kind: Kind
  package let sessionID: String

  package init(kind: Kind, sessionID: String) {
    self.kind = kind
    self.sessionID = sessionID
  }

  // An unknown event is not an error: the listener still answers 200, or the
  // hook would report a failure in the transcript.
  package static func decode(_ data: Data) -> HookEvent? {
    guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
      let name = payload.hookEventName, let kind = Kind(rawValue: name),
      let session = payload.sessionID, !session.isEmpty
    else { return nil }
    return HookEvent(kind: kind, sessionID: session)
  }

  // Only these two fields are decoded, so transcript text never enters through a hook.
  private struct Payload: Decodable {
    let hookEventName: String?
    let sessionID: String?

    enum CodingKeys: String, CodingKey {
      case hookEventName = "hook_event_name"
      case sessionID = "session_id"
    }
  }
}

// Security: a browser page cannot omit `Origin` or choose the host, so refusing
// either keeps pages from posting made-up events.
package enum HookRouter {
  package static func status(for request: HookRequest, port: UInt16?) -> HTTPStatus {
    guard request.path == HookWiring.path else { return .notFound }
    guard request.method == "POST" else { return .methodNotAllowed }
    guard request.headers["origin"] == nil else { return .forbidden }
    guard isOurs(host: request.headers["host"], port: port) else { return .forbidden }
    return .ok
  }

  static func isOurs(host: String?, port: UInt16?) -> Bool {
    guard let host else { return false }
    guard let port else { return true }
    let names = ["\(HookWiring.host):\(port)", "localhost:\(port)"]
    return names.contains(host.lowercased())
  }
}
