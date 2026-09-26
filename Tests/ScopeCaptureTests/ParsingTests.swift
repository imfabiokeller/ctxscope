import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture

@Suite("JSONValue")
struct JSONValueTests {
  @Test("numbers keep their kind")
  func numbers() throws {
    let value = try JSONValue(parsing: Data(#"{"a":1,"b":1.5,"c":true,"d":null}"#.utf8))
    #expect(value["a"]?.int == 1)
    #expect(value["b"]?.double == 1.5)
    #expect(value["c"]?.bool == true)
    #expect(value["d"] == JSONValue.null)
  }

  @Test("unknown shapes read as nil rather than throwing")
  func tolerant() throws {
    let value = try JSONValue(parsing: Data(#"{"type":"something-new","payload":[1,2]}"#.utf8))
    #expect(value["type"]?.string == "something-new")
    #expect(value["payload"]?.array?.count == 2)
    #expect(value["missing"] == nil)
    #expect(value["payload"]?.string == nil)
  }
}

@Suite("JSONLReader")
struct JSONLReaderTests {
  private func write(_ lines: [String]) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "ctxscope-\(UUID().uuidString).jsonl")
    try lines.joined(separator: "\n").appending("\n").write(
      to: url, atomically: true, encoding: .utf8)
    return url
  }

  @Test("reading from a position returns exactly the lines appended since")
  func incremental() throws {
    let url = try write([#"{"type":"user"}"#, #"{"type":"assistant"}"#])
    defer { try? FileManager.default.removeItem(at: url) }
    let first = try JSONLReader(url: url).read()
    #expect(first.entries.count == 2)

    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(
      contentsOf: Data(
        [#"{"type":"attachment"}"#, #"{"type":"system"}"#].joined(separator: "\n")
          .appending("\n").utf8))
    try handle.close()

    let second = try JSONLReader(url: url).read(from: first.position)
    #expect(second.entries.count == 2)
    #expect(second.entries.map { $0.value["type"]?.string } == ["attachment", "system"])
    #expect(second.position.offset > first.position.offset)
    // And reading again from there returns nothing at all.
    #expect(try JSONLReader(url: url).read(from: second.position).entries.isEmpty)
  }

  @Test("a half written last line is skipped, not an error")
  func partialLine() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "ctxscope-\(UUID().uuidString).jsonl")
    try #"{"type":"user"}"#.appending("\n").appending(#"{"type":"assis"#)
      .write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    let result = try JSONLReader(url: url).read()
    #expect(result.entries.count == 1)
  }
}

@Suite("TranscriptEntry")
struct TranscriptEntryTests {
  @Test("timestamps parse without a date formatter")
  func timestamps() {
    #expect(TranscriptEntry.parseTimestamp("1970-01-01T00:00:00.000Z") == 0)
    #expect(TranscriptEntry.parseTimestamp("2026-09-20T22:27:44Z") == 1_789_943_264)
    #expect(TranscriptEntry.parseTimestamp("2026-09-20T22:27:44.500Z") == 1_789_943_264.5)
    #expect(TranscriptEntry.parseTimestamp("not a date") == nil)
  }

  @Test("a string content becomes one text block")
  func stringContent() throws {
    let entry = TranscriptEntry(
      try JSONValue(parsing: Data(#"{"type":"user","message":{"content":"hello"}}"#.utf8)))
    #expect(entry.blocks.count == 1)
    #expect(entry.blocks[0]["text"]?.string == "hello")
  }
}

@Suite("ChainTracker")
struct ChainTrackerTests {
  /// root -> a -> b -> c, and a branch root -> a -> d
  private let parents = ["a": "root", "b": "a", "c": "b", "d": "a", "root": nil as String?]

  @Test("moving forward only adds")
  func forward() {
    var tracker = ChainTracker()
    let first = tracker.move(to: "b") { parents[$0] ?? nil }
    #expect(first.added == ["root", "a", "b"])
    #expect(first.removed.isEmpty)
    let second = tracker.move(to: "c") { parents[$0] ?? nil }
    #expect(second.added == ["c"])
    #expect(second.removed.isEmpty)
  }

  @Test("a branch removes the tail it left behind")
  func branch() {
    var tracker = ChainTracker()
    _ = tracker.move(to: "c") { parents[$0] ?? nil }
    let change = tracker.move(to: "d") { parents[$0] ?? nil }
    #expect(change.removed == ["b", "c"])
    #expect(change.added == ["d"])
    #expect(tracker.chain == ["root", "a", "d"])
  }

  @Test("a chain that starts outside the file is simply a new chain")
  func unknownParent() {
    var tracker = ChainTracker()
    _ = tracker.move(to: "c") { parents[$0] ?? nil }
    let change = tracker.move(to: "elsewhere") { _ in nil }
    #expect(change.added == ["elsewhere"])
    #expect(change.removed.count == 4)
  }
}

@Suite("Band mapping")
struct BandMappingTests {
  @Test("tool results land in the band of the tool that produced them")
  func toolBands() {
    #expect(ClaudeCodeBands.band(forTool: "Read") == .read)
    #expect(ClaudeCodeBands.band(forTool: "Bash") == .bash)
    #expect(ClaudeCodeBands.band(forTool: "Task") == .agent)
    #expect(ClaudeCodeBands.band(forTool: "Grep") == .srch)
    #expect(ClaudeCodeBands.band(forTool: "mcp__todoist__find-tasks") == .srch)
  }

  @Test("memory attachments are memory, reminders are user")
  func attachmentBands() {
    #expect(ClaudeCodeBands.band(forAttachment: "nested_memory") == .mem)
    #expect(ClaudeCodeBands.band(forAttachment: "file") == .read)
    #expect(ClaudeCodeBands.band(forAttachment: "total_tokens_reminder") == .user)
  }

  @Test("a label names the tool and the file, never the content")
  func labels() throws {
    let input = try JSONValue(parsing: Data(#"{"file_path":"/a/b/Segment.swift"}"#.utf8))
    #expect(ClaudeCodeBands.label(tool: "Read", input: input) == "Read Segment.swift")
    #expect(ClaudeCodeBands.label(tool: "Bash", input: nil) == "Bash")
  }
}
