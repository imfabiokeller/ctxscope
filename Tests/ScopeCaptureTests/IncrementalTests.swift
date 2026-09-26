import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture

@Suite("Incremental capture")
struct IncrementalTests {
  static func split(_ name: String, at fraction: Double) throws -> (url: URL, tail: [String]) {
    guard let source = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "jsonl")
    else {
      Issue.record("fixture \(name) is missing")
      throw CocoaError(.fileNoSuchFile)
    }
    let lines = try String(contentsOf: source, encoding: .utf8)
      .split(separator: "\n").map(String.init)
    let cut = Int(Double(lines.count) * fraction)
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "ctxscope-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "session.jsonl")
    try lines[0..<cut].joined(separator: "\n").appending("\n")
      .write(to: url, atomically: true, encoding: .utf8)
    return (url, Array(lines[cut...]))
  }

  static func reference(_ url: URL) -> SessionRef {
    SessionRef(
      id: "test", project: "test", url: url, title: nil, lastActivity: Date(),
      byteSize: 0, isLive: false)
  }

  static func append(_ lines: [String], to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(lines.joined(separator: "\n").appending("\n").utf8))
    try handle.close()
  }

  @Test("a refresh reads only the lines that arrived since the last one")
  func refreshReadsOnlyNewLines() throws {
    let (url, tail) = try Self.split("short-session", at: 0.6)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var capture = SessionCapture(
      session: Self.reference(url), includeSubagents: false, window: nil)

    let first = try capture.refresh()
    #expect(first.newLines > 50)

    let idle = try capture.refresh()
    #expect(idle.newLines == 0)
    #expect(idle.filesRead == 0)

    try Self.append(Array(tail.prefix(10)), to: url)
    let second = try capture.refresh()
    #expect(second.newLines == 10)
    #expect(second.newLines < first.newLines)
  }

  @Test(
    "reading a file in pieces gives the same lane as reading it at once",
    arguments: ["short-session", "compaction-session", "parallel-calls", "subagent-lane"]
  )
  func incrementalMatchesWholeFile(fixture: String) throws {
    let (url, tail) = try Self.split(fixture, at: 0.5)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    var capture = SessionCapture(
      session: Self.reference(url), includeSubagents: false, window: nil)
    try capture.refresh()
    for chunk in stride(from: 0, to: tail.count, by: 7) {
      try Self.append(Array(tail[chunk..<min(chunk + 7, tail.count)]), to: url)
      try capture.refresh()
    }
    let streamed = try #require(capture.finish().recording.mainLane)

    let whole = try AdapterTests.lane(fixture).lane
    #expect(streamed.snapshots.count == whole.snapshots.count)
    #expect(streamed.snapshots.map(\.usage) == whole.snapshots.map(\.usage))
    #expect(streamed.snapshots.map(\.parentRequest) == whole.snapshots.map(\.parentRequest))
    #expect(streamed.segments.count == whole.segments.count)
    #expect(streamed.segments.map(\.tokens) == whole.segments.map(\.tokens))
    #expect(streamed.segments.map(\.band) == whole.segments.map(\.band))
    #expect(streamed.segments.map(\.born) == whole.segments.map(\.born))
    #expect(streamed.segments.map(\.died) == whole.segments.map(\.died))
    #expect(streamed.segments.map(\.deathCause) == whole.segments.map(\.deathCause))
    #expect(streamed.compactions == whole.compactions)
    #expect(streamed.events == whole.events)
    #expect(streamed.window == whole.window)
    // Memory stats describe how the file was read, not the lane.
    var stats = streamed.stats
    stats.heldEntries = whole.stats.heldEntries
    #expect(stats == whole.stats)
  }

  @Test(
    "a judge fed in pieces finds what one fed the whole file finds",
    arguments: ["compaction-session", "parallel-calls"]
  )
  func incrementalJudgeMatches(fixture: String) throws {
    let (url, tail) = try Self.split(fixture, at: 0.5)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    var capture = SessionCapture(
      session: Self.reference(url), includeSubagents: false, window: nil)
    try capture.refresh()
    for chunk in stride(from: 0, to: tail.count, by: 7) {
      try Self.append(Array(tail[chunk..<min(chunk + 7, tail.count)]), to: url)
      try capture.refresh()
    }
    func findings(_ input: JudgeInput) -> [ReferenceFinding] {
      var judge = LexicalJudge(segmentShingleCap: CapturedSession.segmentShingleCap)
      judge.add(input)
      return judge.report().findings
    }
    let streamed = try #require(capture.finish().judgeInputs[.main])
    let whole = try AdapterTests.lane(fixture).judgeInput
    #expect(findings(streamed) == findings(whole))
  }

  @Test("the newest request is published as soon as it starts")
  func newestRequestIsPublishedImmediately() throws {
    var builder = LaneBuilder(id: .main, agentType: nil, parentToolUseID: nil, window: nil)
    builder.append([
      try RequestGroupTests.entry(
        """
        {"type":"user","uuid":"u0","message":{"content":[{"type":"text","text":"go"}]}}
        """),
      try RequestGroupTests.entry(
        """
        {"type":"assistant","uuid":"a1","parentUuid":"u0","requestId":"r1",
         "message":{"model":"m","content":[{"type":"text","text":"first"}],
         "usage":{"input_tokens":1,"cache_read_input_tokens":99,
         "cache_creation_input_tokens":0,"output_tokens":7}}}
        """),
    ])
    let early = builder.snapshotOutput().lane
    #expect(early.snapshots.count == 1)
    #expect(early.snapshots[0].usage.promptTotal == 100)
    #expect(early.snapshots[0].usage.outputTokens == 7)

    builder.append([
      try RequestGroupTests.entry(
        """
        {"type":"assistant","uuid":"a2","parentUuid":"a1","requestId":"r1",
         "message":{"model":"m","stop_reason":"end_turn",
         "content":[{"type":"text","text":"and the rest of it"}],
         "usage":{"input_tokens":1,"cache_read_input_tokens":99,
         "cache_creation_input_tokens":0,"output_tokens":220}}}
        """)
    ])
    let later = builder.snapshotOutput().lane
    #expect(later.snapshots.count == 1)
    #expect(later.snapshots[0].usage.promptTotal == 100)
    #expect(later.snapshots[0].usage.outputTokens == 220)
    #expect(builder.finish().lane.snapshots.count == 1)
  }

  @Test("the reader streams rather than holding the file")
  func readerStreams() throws {
    let (url, _) = try Self.split("short-session", at: 1.0)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var lines = 0
    var biggest = 0
    let end = try JSONLReader(url: url).stream { data, _ in
      lines += 1
      biggest = max(biggest, data.count)
    }
    let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
    #expect(lines > 100)
    #expect(end.offset == UInt64(size))
    #expect(biggest < size / 2)
  }

  @Test("a half written last line is left for the next refresh")
  func partialLineIsNotConsumed() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "ctxscope-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "session.jsonl")
    try #"{"type":"user","uuid":"a"}"#.appending("\n").appending(#"{"type":"assis"#)
      .write(to: url, atomically: true, encoding: .utf8)

    let first = try JSONLReader(url: url).read()
    #expect(first.entries.count == 1)
    #expect(first.skipped == 0)

    try Self.append([#"tant","uuid":"b"}"#], to: url)
    let second = try JSONLReader(url: url).read(from: first.position)
    #expect(second.entries.count == 1)
    #expect(second.entries.first?.value["uuid"]?.string == "b")
  }
}
