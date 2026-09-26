import Foundation
import ScopeCapture
import ScopeCore
import Testing

@testable import ctxscope_cli

@Suite("demo session")
struct DemoTests {
  static let start = Date(timeIntervalSince1970: 1_790_000_000)

  static func written(live: Bool = false) throws -> (home: URL, session: DemoSession) {
    let home = FileManager.default.temporaryDirectory
      .appending(path: "ctxscope-demo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let session = DemoSession(home: home, day: start)
    let schedule =
      live
      ? DemoSchedule.live(
        gaps: session.gaps, batch: DemoSession.liveBatch, now: start, seconds: 0)
      : DemoSchedule.story(gaps: session.gaps, start: start)
    try session.write(try session.chunks(schedule))
    return (home, session)
  }

  static func capture(_ home: URL) throws -> (SessionRef, CapturedSession) {
    let adapter = ClaudeCodeAdapter(root: home.appending(path: ".claude/projects"))
    let sessions = try adapter.sessions()
    let session = try #require(sessions.first)
    #expect(sessions.count == 1)
    return (session, try adapter.capture(session))
  }

  @Test("87 requests, 9 prompts, two subagent lanes, filed under the project")
  func shape() throws {
    let (home, demo) = try Self.written()
    defer { try? FileManager.default.removeItem(at: home) }
    let (session, captured) = try Self.capture(home)
    #expect(session.title == "retry-policy")
    #expect(session.project == demo.project.cwd)
    #expect(session.project.hasSuffix("/code/api-client"))

    let main = try #require(captured.recording.mainLane)
    #expect(main.snapshots.count == 87)
    #expect(main.prompts.count == 9)
    #expect(captured.recording.lanes.count == 3)
    #expect(
      Set(captured.recording.lanes.compactMap(\.agentType)) == ["Explore", "general-purpose"])
    for lane in captured.recording.lanes {
      #expect(Validator.run(lane).mismatches.isEmpty)
    }
  }

  @Test("three cache breaks, at 23, 42 and 64, for the reasons the story gives")
  func breaks() throws {
    let (home, _) = try Self.written()
    defer { try? FileManager.default.removeItem(at: home) }
    let main = try #require(try Self.capture(home).1.recording.mainLane)
    let busts = CacheAnalyzer.run(main).busts
    #expect(busts.map { RequestNumber.of($0.request) } == [23, 42, 64])
    #expect(busts.map(\.cause) == [.memoryChanged, .idle, .toolsChanged])
    #expect(busts[1].gapSeconds >= CacheAnalyzer.idleSeconds)
    #expect(busts[2].change?.servers == ["github"])
    #expect(busts[0].readThrough == .tools)
    #expect(busts[2].readThrough == .tools)
  }

  @Test("it ends near 140k, with no block for an MCP server that was not there")
  func size() throws {
    let (home, _) = try Self.written()
    defer { try? FileManager.default.removeItem(at: home) }
    let main = try #require(try Self.capture(home).1.recording.mainLane)
    let last = try #require(main.snapshots.last).usage.promptTotal
    #expect((130_000...150_000).contains(last))
    #expect(!main.segments.contains { $0.band == .mcp && $0.born == 0 })
    #expect(main.segments.count { $0.band == .mcp } == 26)
  }

  @Test("a live run's first batch ends before the pause, and the rest is the same session")
  func live() throws {
    let (home, _) = try Self.written(live: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let main = try #require(try Self.capture(home).1.recording.mainLane)
    #expect(main.snapshots.count == 87)
    #expect(CacheAnalyzer.run(main).busts.map(\.cause) == [.memoryChanged, .idle, .toolsChanged])
  }

  @Test("the same story gives the same files")
  func deterministic() throws {
    let first = try Self.written()
    let second = try Self.written()
    defer {
      try? FileManager.default.removeItem(at: first.home)
      try? FileManager.default.removeItem(at: second.home)
    }
    let one = try String(contentsOf: first.session.transcript, encoding: .utf8)
    let two = try String(contentsOf: second.session.transcript, encoding: .utf8)
    #expect(
      one.replacingOccurrences(of: first.home.path, with: "")
        == two.replacingOccurrences(of: second.home.path, with: ""))
  }
}
