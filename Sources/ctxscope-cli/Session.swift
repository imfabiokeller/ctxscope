import Foundation
import ScopeCapture
import ScopeCore

/// Shared loading, so every command opens a session the same way.
enum Loader {
  static func adapter(_ arguments: Arguments) -> ClaudeCodeAdapter {
    ClaudeCodeAdapter(contextWindow: arguments.integer("window"))
  }

  static func capture(_ arguments: Arguments) throws -> (
    session: SessionRef, captured: CapturedSession
  ) {
    guard let id = arguments.first else {
      throw CLIError.usage("a session id is required, try: ctxscope sessions")
    }
    let adapter = adapter(arguments)
    let session = try adapter.session(matching: id)
    let captured = try adapter.capture(session, includeSubagents: !arguments.has("no-subagents"))
    return (session, captured)
  }

  /// One judge per lane, fed that lane's input.
  static func references(_ captured: CapturedSession, _ lane: Lane) -> ReferenceReport {
    var judge = LexicalJudge(segmentShingleCap: CapturedSession.segmentShingleCap)
    if let input = captured.judgeInputs[lane.id] { judge.add(input) }
    return judge.report()
  }

  static func lane(_ captured: CapturedSession, _ arguments: Arguments) throws -> Lane {
    if let id = arguments.value("lane") {
      guard let lane = captured.recording.lane(LaneID(id)) else {
        let known = captured.recording.lanes.map(\.id.rawValue).joined(separator: ", ")
        throw CLIError.usage("no lane \(id). lanes: \(known)")
      }
      return lane
    }
    guard let main = captured.recording.mainLane else {
      throw CLIError.usage("the session has no requests")
    }
    return main
  }
}

enum SessionsCommand {
  static func run(_ arguments: Arguments) throws {
    let all = try Loader.adapter(arguments).sessions()
    let filtered =
      arguments.value("project").map { needle in
        all.filter { $0.project.localizedCaseInsensitiveContains(needle) }
      } ?? all
    let limit = arguments.integer("limit") ?? 20

    Console.out(
      TokenFormat.padRight("session", to: 10) + "  "
        + TokenFormat.padRight("project", to: 38) + "  "
        + TokenFormat.pad("size", to: 9) + "  "
        + TokenFormat.padRight("last activity", to: 20) + "  live  title")
    for session in filtered.prefix(limit) {
      Console.out(
        TokenFormat.padRight(String(session.id.prefix(8)), to: 10) + "  "
          + TokenFormat.padRight(session.project, to: 38) + "  "
          + TokenFormat.pad(TokenFormat.bytes(session.byteSize), to: 9) + "  "
          + TokenFormat.padRight(stamp(session.lastActivity), to: 20) + "  "
          + (session.isLive ? " yes  " : "  no  ")
          + (session.title ?? ""))
    }
    Console.out("")
    Console.out("\(filtered.count) sessions, showing \(min(limit, filtered.count))")
  }

  private static func stamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
  }
}
