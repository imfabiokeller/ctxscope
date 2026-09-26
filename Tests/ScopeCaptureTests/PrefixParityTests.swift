import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture

/// A lane is the same lane however the file was read.
///
/// The records that describe the prefix sit wherever the harness wrote them,
/// and the prefix is derived at the first request, so a capture that starts
/// reading before one of them arrives used to build a different lane: a first
/// read at line 22, 26 or 30 of the short session gave one tool block where a
/// whole read gave forty-five. A new chat where `/ctxscope` is the first
/// prompt is exactly that case.
@Suite("prefix parity")
struct PrefixParityTests {
  static let fixtures = ["short-session", "compaction-session", "subagent-lane", "parallel-calls"]

  /// A lane, as much of it as has to match: what is in the context, in what
  /// order, at what size, from when to when.
  struct Shape: Equatable {
    let source: PrefixSplit.Source
    let requests: Int
    let reportRequest: Int?
    let blocks: [String]

    init(_ lane: Lane) {
      source = lane.prefixSource
      requests = lane.snapshots.count
      reportRequest = lane.contextReport?.request
      blocks = lane.segments.map {
        "\($0.band.rawValue)|\($0.label)|\($0.tokens.value)|\($0.born)|\($0.died ?? -1)"
      }
    }
  }

  static func lines(_ name: String) throws -> [String] {
    guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "jsonl")
    else {
      Issue.record("fixture \(name) is missing")
      throw CocoaError(.fileNoSuchFile)
    }
    return try String(contentsOf: url, encoding: .utf8)
      .split(separator: "\n").map(String.init)
  }

  /// Reads a fixture through `SessionCapture`, showing it `cuts` at a time.
  static func shape(_ name: String, cuts: [Int]) throws -> Shape {
    let lines = try Self.lines(name)
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "ctxscope-parity-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "session.jsonl")
    FileManager.default.createFile(atPath: url.path, contents: nil)

    var capture = SessionCapture(
      session: IncrementalTests.reference(url), includeSubagents: false, window: nil)
    var written = 0
    for cut in (cuts + [lines.count]).map({ min($0, lines.count) }) where cut > written {
      try IncrementalTests.append(Array(lines[written..<cut]), to: url)
      written = cut
      _ = try capture.refresh()
    }
    return Shape(try #require(capture.finish().recording.mainLane))
  }

  /// Every way of reading a file gives the same lane: whole, in the batches
  /// the capture reads in, one entry at a time, and stopping at any of the
  /// lines the prefix records sit on or near.
  @Test("a lane is the same however its file was read", arguments: fixtures)
  func sameLaneEveryWay(name: String) throws {
    let count = try Self.lines(name).count
    let whole = try Self.shape(name, cuts: [])
    #expect(whole.requests > 3)
    #expect(!whole.blocks.isEmpty)

    var starts = [1, 2, 5, 10, 18, 20, 22, 24, 26, 28, 30, 31, 40, 60]
    starts += stride(from: 0, to: count, by: max(1, count / 8))
    for start in Set(starts).sorted() where start > 0 && start < count {
      let split = try Self.shape(name, cuts: [start])
      #expect(split == whole, "first read of \(start) lines of \(name)")
    }
    // One entry at a time, which is the slowest a live session can arrive.
    let single = try Self.shape(name, cuts: Array(1..<min(count, 64)))
    #expect(single == whole, "one entry at a time, \(name)")
  }

  /// The rebuild happens at most once per piece of evidence, so following a
  /// live lane does not read the file again on every refresh.
  @Test("a lane is built again only when the prefix evidence is new")
  func rebuildsOnce() throws {
    let lines = try Self.lines("short-session")
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "ctxscope-parity-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "session.jsonl")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    var capture = SessionCapture(
      session: IncrementalTests.reference(url), includeSubagents: false, window: nil)

    // Up to the first response, which is before the tool list is written.
    try IncrementalTests.append(Array(lines[0..<24]), to: url)
    #expect(try capture.refresh().rebuiltLanes == 0)
    // The rest, which carries it.
    try IncrementalTests.append(Array(lines[24...]), to: url)
    #expect(try capture.refresh().rebuiltLanes == 1)
    // Nothing new to learn, so nothing is read again.
    try IncrementalTests.append([lines[lines.count - 1]], to: url)
    #expect(try capture.refresh().rebuiltLanes == 0)
    #expect(try capture.refresh().rebuiltLanes == 0)
  }

  /// A compaction drops the chain. The blocks the transcript recorded about
  /// the prefix are not on it and must not go with it: they were owned by the
  /// snapshot entry before, so thirteen system prompt blocks died at the
  /// compaction and none came back, while a lane with no snapshot re-derived
  /// its prefix at the same point.
  @Test("the recorded prefix survives a compaction")
  func prefixSurvivesCompaction() throws {
    let snapshots = try Self.lines("short-session").filter { $0.contains("prompt_snapshot") }
    #expect(snapshots.count == 2)
    let lines = snapshots + (try Self.lines("compaction-session"))

    let directory = FileManager.default.temporaryDirectory
      .appending(path: "ctxscope-parity-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "session.jsonl")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    try IncrementalTests.append(lines, to: url)

    var capture = SessionCapture(
      session: IncrementalTests.reference(url), includeSubagents: false, window: nil)
    try capture.refresh()
    let lane = try #require(capture.finish().recording.mainLane)
    let compaction = try #require(lane.compactions.first).atRequest
    #expect(compaction > 0)

    let prefix = lane.segments.filter {
      BandRegistry.family(of: $0.band) == .prefix && $0.born == 0
    }
    #expect(prefix.count { $0.band == .sys } == 13)
    #expect(prefix.count { $0.band == .tools } > 5)
    #expect(prefix.count { $0.band == .mcp } > 5)
    // Not one of them leaves with the chain. They used to be owned by the
    // snapshot entry, so the compaction took all thirteen system prompt
    // blocks and nothing brought them back.
    #expect(prefix.allSatisfy { $0.deathCause != .chain && $0.deathCause != .compaction })
    // The retirement reaches into the prefix only when nothing else is left to
    // cover the overhang, and then takes one block, not the band. This lane is
    // a snapshot of one session over the measured totals of another, so its
    // prefix really is larger than the request after the compaction; a real
    // lane has no such contradiction. Before the rule was split in two, 14 of
    // 15 tool blocks and 17 of 30 MCP blocks went here.
    #expect(prefix.count { $0.isLive(at: compaction) } >= prefix.count - 1)
    #expect(Validator.run(lane).passed)
  }
}
