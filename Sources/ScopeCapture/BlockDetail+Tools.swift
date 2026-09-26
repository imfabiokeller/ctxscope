internal import Foundation
internal import ScopeCore

/// A tool call's detail: the input that says what the call did.
extension BlockDetail {
  /// Inputs that say what an unknown tool was asked, in the order they are
  /// looked for.
  static let telling = [
    "description", "query", "pattern", "url", "file_path", "path", "skill", "subject",
    "summary", "command", "prompt",
  ]

  /// The detail of a call to `tool` with `input`. `result` is what the
  /// harness recorded about the result beside it, when there is one, which
  /// is where a search's count is. `project` is the folder the session ran
  /// in. Nil when the input says nothing that could be shown.
  ///
  /// The call itself is headed "Bash call", so it does not read as the
  /// result it asked for.
  static func tool(
    _ tool: String, input: JSONValue?, result: JSONValue? = nil, project: String?,
    isCall: Bool = false
  ) -> BlockDetail? {
    let suffix = isCall ? " call" : ""
    if let (server, name) = mcp(tool) {
      return BlockDetail(head: server + suffix, detail: cut(name))
    }
    guard let text = told(tool, input: input, result: result, project: project) else {
      return nil
    }
    return BlockDetail(head: tool + suffix, detail: text)
  }

  private static func told(
    _ tool: String, input: JSONValue?, result: JSONValue?, project: String?
  ) -> String? {
    func string(_ key: String) -> String? {
      input?[key]?.string.flatMap { $0.allSatisfy(\.isWhitespace) ? nil : $0 }
    }
    switch tool {
    case "Bash":
      return (string("description") ?? string("command")).map(cut)
    case "Read", "Edit", "Write", "MultiEdit", "NotebookEdit", "NotebookRead":
      return (string("file_path") ?? string("notebook_path")).map { path($0, project: project) }
    case "Grep", "Glob":
      guard let pattern = string("pattern") else { return nil }
      let quoted = "\"\(middle(pattern, limit: limit - 20))\""
      return count(tool, result).map { "\(quoted) (\($0))" } ?? quoted
    case "WebFetch":
      return string("url").map(place)
    case "WebSearch":
      return string("query").map { "\"\(middle($0, limit: limit - 2))\"" }
    case "Agent", "Task":
      return (string("description") ?? string("subagent_type")).map(cut)
    default:
      return telling.lazy.compactMap(string).first.map(cut)
    }
  }

  /// "github" and "create_issue" of "mcp__github__create_issue".
  static func mcp(_ tool: String) -> (String, String)? {
    guard tool.hasPrefix("mcp__") else { return nil }
    let parts = tool.dropFirst(5).components(separatedBy: "__")
    guard parts.count >= 2, !parts[0].isEmpty else { return nil }
    return (parts[0], parts.dropFirst().joined(separator: "__"))
  }

  /// A URL's host and path, without the scheme, the query or "www.".
  static func place(_ url: String) -> String {
    guard let parts = URLComponents(string: url), let host = parts.host else { return cut(url) }
    let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    let path = parts.path == "/" ? "" : parts.path
    return middle(bare + path, limit: limit)
  }

  /// "212 matches" or "8 files", from what the harness recorded about a
  /// search's result.
  private static func count(_ tool: String, _ result: JSONValue?) -> String? {
    guard let result else { return nil }
    let mode = result["mode"]?.string
    if tool == "Grep", mode != "files_with_matches",
      let matches = result["numMatches"]?.int ?? result["numLines"]?.int
    {
      return "\(TokenFormat.count(matches)) \(matches == 1 ? "match" : "matches")"
    }
    return result["numFiles"]?.int.map { TokenFormat.plural($0, "file") }
  }

}
