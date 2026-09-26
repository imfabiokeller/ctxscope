package import Foundation

package struct Layout: Sendable {
  package let unit: String
  package let breakLine: String

  package init(unit: String = "  ", breakLine: String = "\n") {
    self.unit = unit
    self.breakLine = breakLine
  }

  package init(reading data: Data) {
    unit = SourceText.indentUnit(in: data)
    breakLine = SourceText.lineBreak(in: data)
  }
}

package enum HookWiring {
  package static let host = "127.0.0.1"
  // The path is the tag that finds our entries again, without a field the format
  // does not know.
  package static let path = "/ctxscope/hook"

  package static let events = ["SessionEnd"]

  // `SessionStart` runs only `command` and `mcp_tool` hooks, so wake is a command.
  package static let wakeEvent = "SessionStart"

  package static var allEvents: [String] { events + [wakeEvent] }

  // No `compact`: it fires inside a running session and would undo a power
  // control somebody just pressed.
  package static let wakeMatcher = "startup|resume|clear|fork"

  // `open` passes arguments only when it launches the app, so a running
  // ctxscope never sees this flag.
  package static let wokenFlag = "--woken"

  // `|| true`: a missing ctxscope is not something a session should report.
  package static var wakeCommand: String {
    "open -g \(ScopeURL.wake) --args \(wokenFlag) || true"
  }

  // Not enforced while `async` is true; it applies to a Claude Code that does
  // not know `async`.
  package static let wakeTimeout = 5

  // The shortest the format takes; only reached when ctxscope is not running.
  package static let timeout = 1

  // Unassigned, and below the range macOS hands out to outgoing connections.
  package static let defaultPort: UInt16 = 45871
  package static let portAttempts = 8

  package static func url(port: UInt16) -> String { "http://\(host):\(port)\(path)" }

  package static let disableKey = "disableAllHooks"
  package static let allowListKey = "allowedHttpHookUrls"

  // These settings also merge from project and managed files, which are not
  // read here, so this speaks only for this file.
  package static func blocker(in data: Data, port: UInt16?) -> String? {
    guard let root = try? JSONSpan.parse(data) else { return nil }
    if root[disableKey]?.flag == true {
      return "\(disableKey) is on in this settings file, so no hooks run"
    }
    guard let allowed = root[allowListKey]?.elements else { return nil }
    let wanted = url(port: port ?? defaultPort)
    guard !allowed.compactMap(\.text).contains(where: { allows($0, wanted) }) else { return nil }
    return "\(allowListKey) does not list ctxscope's URL, so its hooks would not run"
  }

  private static func allows(_ entry: String, _ wanted: String) -> Bool {
    guard entry.hasSuffix("*") else { return entry == wanted }
    return wanted.hasPrefix(entry.dropLast())
  }

  package static func port(ofURL text: String) -> UInt16? {
    guard let url = URL(string: text), url.path == path, url.host == host,
      let port = url.port, let value = UInt16(exactly: port)
    else { return nil }
    return value
  }

  package static func isOurs(handler: JSONSpan) -> Bool {
    if handler["type"]?.text == "http" {
      return (handler["url"]?.text).flatMap(port(ofURL:)) != nil
    }
    guard handler["type"]?.text == "command", let command = handler["command"]?.text else {
      return false
    }
    return command.contains(ScopeURL.wake)
  }

  package static func isOurs(group: JSONSpan) -> Bool {
    guard let handlers = group["hooks"]?.elements, !handlers.isEmpty else { return false }
    return handlers.allSatisfy(isOurs(handler:))
  }

  // No `matcher`: an omitted matcher matches everything.
  package static func group(port: UInt16, indent: String, layout: Layout) -> String {
    let one = indent + layout.unit
    let two = one + layout.unit
    let three = two + layout.unit
    return [
      "{",
      one + "\"hooks\": [",
      two + "{",
      three + "\"type\": \"http\",",
      three + "\"url\": \"\(url(port: port))\",",
      three + "\"timeout\": \(timeout)",
      two + "}",
      one + "]",
      indent + "}",
    ].joined(separator: layout.breakLine)
  }

  package static func wakeGroup(indent: String, layout: Layout) -> String {
    let one = indent + layout.unit
    let two = one + layout.unit
    let three = two + layout.unit
    return [
      "{",
      one + "\"matcher\": \"\(wakeMatcher)\",",
      one + "\"hooks\": [",
      two + "{",
      three + "\"type\": \"command\",",
      three + "\"command\": \"\(wakeCommand)\",",
      three + "\"async\": true,",
      three + "\"timeout\": \(wakeTimeout)",
      two + "}",
      one + "]",
      indent + "}",
    ].joined(separator: layout.breakLine)
  }

  package static func array(event: String, port: UInt16, indent: String, layout: Layout) -> String {
    let one = indent + layout.unit
    let only =
      event == wakeEvent
      ? wakeGroup(indent: one, layout: layout) : group(port: port, indent: one, layout: layout)
    return "[" + layout.breakLine + one + only + layout.breakLine + indent + "]"
  }

  package static func hooksObject(port: UInt16, indent: String, layout: Layout) -> String {
    let one = indent + layout.unit
    let entries = allEvents.map { event in
      one + "\"\(event)\": " + array(event: event, port: port, indent: one, layout: layout)
    }
    return "{" + layout.breakLine + entries.joined(separator: "," + layout.breakLine)
      + layout.breakLine + indent + "}"
  }
}
