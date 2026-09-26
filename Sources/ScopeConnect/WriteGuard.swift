package import Foundation

package enum Refusal: Error, CustomStringConvertible, Equatable {
  case notJSON(String)
  case notAnObject
  case notReadable
  // Claude Code reads the last duplicate key and ctxscope would edit the first.
  case repeatedKey(String)
  case wouldNotBeReadable
  case wouldNotComeBack
  case moved
  case readOnly(String)
  case danglingLink(String)

  package var description: String {
    switch self {
    case .notJSON(let what):
      "the settings file is not JSON: \(what), so ctxscope left it alone"
    case .notAnObject:
      "the settings file is not a JSON object, so ctxscope left it alone"
    case .notReadable:
      "ctxscope could not read the settings file safely, so it left it alone"
    case .repeatedKey(let key):
      "\"\(key)\" is written twice in the settings file, so ctxscope cannot tell "
        + "which one Claude Code uses"
    case .wouldNotBeReadable:
      "the change would leave a settings file Claude Code could not read, so nothing was written"
    case .wouldNotComeBack:
      "the change could not be taken back exactly, so nothing was written"
    case .moved:
      "the settings file changed since this was worked out"
    case .readOnly(let name):
      "\(name) is read only, so ctxscope left it alone"
    case .danglingLink(let name):
      "\(name) is a link to nothing ctxscope could write, so it left it alone"
    }
  }
}

package enum WriteGuard {
  // The span parser goes first to name the bad line; Foundation second, as it
  // is closer to what the harness does.
  package static func check(readable data: Data) throws {
    let root: JSONSpan
    do {
      root = try JSONSpan.parse(data)
    } catch let invalid as JSONSpan.Invalid {
      throw Refusal.notJSON(invalid.description)
    }
    guard case .object = root.kind else { throw Refusal.notAnObject }
    guard (try? JSONSerialization.jsonObject(with: data)) != nil else { throw Refusal.notReadable }
    if let repeated = repeatedKey(root) { throw Refusal.repeatedKey(repeated) }
  }

  package static func isWellFormed(_ data: Data) -> Bool {
    (try? check(readable: data)) != nil
  }

  // Safety: the harness must read the result, and removing ctxscope again must
  // give back exactly the bytes from before.
  package static func check(_ current: Data?, backup: Data?, becomes next: Data) throws {
    guard isWellFormed(next) else { throw Refusal.wouldNotBeReadable }
    guard let current, !SettingsEdit.isBlank(current) else { return }
    guard let bare = try? SettingsEdit.disconnected(current, original: backup),
      (try? SettingsEdit.disconnected(next, original: bare)) == bare
    else { throw Refusal.wouldNotComeBack }
  }

  private static func repeatedKey(_ value: JSONSpan) -> String? {
    switch value.kind {
    case .object(let members):
      var seen: Set<String> = []
      for member in members {
        guard seen.insert(member.name).inserted else { return member.name }
        if let found = repeatedKey(member.value) { return found }
      }
    case .array(let elements):
      for element in elements {
        if let found = repeatedKey(element) { return found }
      }
    default: break
    }
    return nil
  }
}
