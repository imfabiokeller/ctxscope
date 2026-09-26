package import Foundation

/// How the file is laid out, so what ctxscope writes looks like what is
/// already there.
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

/// The hook entries ctxscope adds to a settings file, and how to recognise one
/// again.
///
/// Verified against the hooks reference at code.claude.com/docs/en/hooks.md on
/// 2026-09-21. HTTP hooks are `{"type": "http", "url": ...}` handlers inside a
/// matcher group, the group sits in an array under the event name, and the
/// event names sit under `hooks`. `timeout` is per handler and in seconds.
package enum HookWiring {
  package static let host = "127.0.0.1"
  /// The path is the tag: nothing else on this machine answers on it, so our
  /// entries can be found again without adding a field the format does not
  /// know.
  package static let path = "/ctxscope/hook"

  /// The events ctxscope listens for. One.
  ///
  /// It used to be six. Five of them said "this session is working now", and
  /// the file watcher says that on its own within a fraction of a second,
  /// from the file the work is written to. A hook that repeats what the
  /// watcher already knows is an entry in somebody else's settings file for
  /// nothing.
  ///
  /// `SessionEnd` is the one thing no file says: a transcript that has
  /// stopped growing looks exactly like a session that has ended, and the
  /// difference is three minutes of the item claiming a session is live.
  ///
  /// `SessionStart` is not an HTTP hook. The reference says it runs `command`
  /// and `mcp_tool` hooks only, which is what the wake entry below is.
  package static let events = ["SessionEnd"]

  /// The one event ctxscope answers with a command rather than a URL, because
  /// a refused connection starts nothing. `SessionStart` takes `command` and
  /// `mcp_tool` hooks only, which is what makes this the shape it has.
  package static let wakeEvent = "SessionStart"

  /// Every event ctxscope writes an entry for.
  package static var allEvents: [String] { events + [wakeEvent] }

  /// A session starting is the moment to be there. A compaction is not: it
  /// fires `SessionStart` inside a session that is already running, and
  /// waking there would undo a power control somebody had just pressed.
  package static let wakeMatcher = "startup|resume|clear|fork"

  /// The flag the launched application is handed, so it can tell a launch a
  /// session caused from someone opening the app. `open` passes arguments
  /// only when it actually launches something: a ctxscope that is already
  /// running gets the URL and nothing else.
  package static let wokenFlag = "--woken"

  /// What that hook runs. No quotes, because the URL has nothing in it a
  /// shell would touch, and `|| true` because ctxscope not being installed is
  /// not something a session should be told about.
  package static var wakeCommand: String {
    "open -g \(ScopeURL.wake) --args \(wokenFlag) || true"
  }

  /// Seconds. Not enforced while `async` is true, which the reference says
  /// outright; it is what would apply to a Claude Code that does not know the
  /// field and runs the hook in front of the session instead.
  package static let wakeTimeout = 5

  /// Seconds, whole ones, and the shortest the format takes. The listener
  /// answers before it does any work, so this is only ever reached when
  /// ctxscope is not running, and a refused connection is reported at once.
  package static let timeout = 1

  /// The port ctxscope asks for first. Unassigned, and below the range macOS
  /// hands out to outgoing connections.
  package static let defaultPort: UInt16 = 45871
  /// How many ports past that one to try when it is taken.
  package static let portAttempts = 8

  package static func url(port: UInt16) -> String { "http://\(host):\(port)\(path)" }

  /// Settings that stop hooks running whatever is written under `hooks`.
  /// Neither is something ctxscope writes or removes, so all it can do is say
  /// so in one line.
  package static let disableKey = "disableAllHooks"
  package static let allowListKey = "allowedHttpHookUrls"

  /// What in this settings file would keep ctxscope's hooks from running.
  ///
  /// Both settings merge across the project and managed files too, which
  /// ctxscope does not read, so this can only speak for the one in front of
  /// it.
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

  /// One entry of the allow list against our URL. An entry ending in a star
  /// covers what starts with the rest of it, which is the only pattern worth
  /// reading without a rule written down for it.
  private static func allows(_ entry: String, _ wanted: String) -> Bool {
    guard entry.hasSuffix("*") else { return entry == wanted }
    return wanted.hasPrefix(entry.dropLast())
  }

  /// The port one of our URLs points at, or nil when the URL is not ours.
  package static func port(ofURL text: String) -> UInt16? {
    guard let url = URL(string: text), url.path == path, url.host == host,
      let port = url.port, let value = UInt16(exactly: port)
    else { return nil }
    return value
  }

  /// True when this handler is one ctxscope wrote. Either the URL is ours, or
  /// the command is the one that wakes us: a command string nothing else on
  /// this machine would have.
  package static func isOurs(handler: JSONSpan) -> Bool {
    if handler["type"]?.text == "http" {
      return (handler["url"]?.text).flatMap(port(ofURL:)) != nil
    }
    guard handler["type"]?.text == "command", let command = handler["command"]?.text else {
      return false
    }
    return command.contains(ScopeURL.wake)
  }

  /// True when every handler in this matcher group is ours, which is what a
  /// group ctxscope wrote looks like.
  package static func isOurs(group: JSONSpan) -> Bool {
    guard let handlers = group["hooks"]?.elements, !handlers.isEmpty else { return false }
    return handlers.allSatisfy(isOurs(handler:))
  }

  // MARK: what gets written

  /// One matcher group with our handler in it. No `matcher` field: an omitted
  /// matcher matches everything, and four of these six events take no matcher
  /// at all.
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

  /// The matcher group that starts ctxscope when a session begins.
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

  /// One event's array, for a settings file whose `hooks` has no entry for it.
  package static func array(event: String, port: UInt16, indent: String, layout: Layout) -> String {
    let one = indent + layout.unit
    let only =
      event == wakeEvent
      ? wakeGroup(indent: one, layout: layout) : group(port: port, indent: one, layout: layout)
    return "[" + layout.breakLine + one + only + layout.breakLine + indent + "]"
  }

  /// The whole `hooks` object, for a settings file that has none.
  package static func hooksObject(port: UInt16, indent: String, layout: Layout) -> String {
    let one = indent + layout.unit
    let entries = allEvents.map { event in
      one + "\"\(event)\": " + array(event: event, port: port, indent: one, layout: layout)
    }
    return "{" + layout.breakLine + entries.joined(separator: "," + layout.breakLine)
      + layout.breakLine + indent + "}"
  }
}
