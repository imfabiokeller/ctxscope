package import Foundation

/// What ctxscope will not do to a settings file, in the words a person reads.
package enum Refusal: Error, CustomStringConvertible, Equatable {
  /// It is not JSON at all. The text says where.
  case notJSON(String)
  /// It is JSON, but not an object, so it is not a settings file.
  case notAnObject
  /// It parses here and not in Foundation: a NUL byte, bytes that are not
  /// UTF-8, a lone surrogate, a number nothing else accepts.
  case notReadable
  /// The same key twice. Claude Code reads the last one and ctxscope would
  /// edit the first.
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

/// The checks in front of every write.
///
/// Two jobs that are not editing, which is why they are not in `SettingsEdit`:
/// deciding whether a file may be touched at all, and deciding whether what
/// would go out is safe. Neither is asserted after the fact, so a file that
/// would fail is never written.
package enum WriteGuard {
  /// The file as it stands, read the way ctxscope has to read it.
  ///
  /// The span parser goes first, because it is the one that can say which
  /// line is wrong. Foundation goes second, because it is closer to what the
  /// harness does. A key written twice is read one way here and the other way
  /// there, and a file read two ways is a file that can be damaged.
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

  /// What goes out has to be a file the harness reads, and taking ctxscope
  /// back out of it has to give exactly the bytes that were there before
  /// ctxscope wrote anything.
  ///
  /// The bytes it compares against are the file as it stands with our entries
  /// taken out, which is the same file whether or not ctxscope has written to
  /// it before.
  package static func check(_ current: Data?, backup: Data?, becomes next: Data) throws {
    guard isWellFormed(next) else { throw Refusal.wouldNotBeReadable }
    guard let current, !SettingsEdit.isBlank(current) else { return }
    guard let bare = try? SettingsEdit.disconnected(current, original: backup),
      (try? SettingsEdit.disconnected(next, original: bare)) == bare
    else { throw Refusal.wouldNotComeBack }
  }

  /// The first key written twice, anywhere in the document.
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
