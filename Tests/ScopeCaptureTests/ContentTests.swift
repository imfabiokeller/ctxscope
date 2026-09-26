import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture

@Suite("Segment content")
struct ContentTests {
  static func reference(_ name: String) throws -> SessionRef {
    guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "jsonl")
    else {
      Issue.record("fixture \(name) is missing")
      throw CocoaError(.fileNoSuchFile)
    }
    return SessionRef(
      id: name, project: "test", url: url, title: nil, lastActivity: Date(),
      byteSize: 0, isLive: false)
  }

  @Test("a segment's text is read back out of the transcript")
  func contentComesBackFromTheFile() throws {
    var capture = SessionCapture(
      session: try Self.reference("short-session"), includeSubagents: false, window: nil)
    try capture.refresh()
    let session = capture.finish()
    let lane = try #require(session.recording.mainLane)

    var served = 0
    for segment in lane.segments where segment.characters > 0 {
      guard let content = capture.content(of: segment.id) else { continue }
      served += 1
      #expect(content.segment == segment.id)
      #expect(content.band == segment.band)
      #expect(!content.text.isEmpty)
    }
    let recorded = lane.segments.filter { $0.characters > 0 }.count
    #expect(served == recorded)
  }

  @Test("the text a segment gives back is the text the judge shingled")
  func contentMatchesTheJudgesView() throws {
    var capture = SessionCapture(
      session: try Self.reference("short-session"), includeSubagents: false, window: nil)
    try capture.refresh()
    let session = capture.finish()
    let lane = try #require(session.recording.mainLane)
    let input = try #require(session.judgeInputs[lane.id])
    let byID = Dictionary(
      lane.segments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var checked = 0
    for judged in input.segments where !judged.shingles.isEmpty {
      guard let segment = byID[judged.id],
        segment.band != .tools, segment.band != .mcp,
        let content = capture.content(of: judged.id)
      else { continue }
      let all = Set(Shingler.shingles(of: content.text))
      #expect(Set(judged.shingles).isSubset(of: all))
      checked += 1
      if checked > 40 { break }
    }
    #expect(checked > 0)
  }

  @Test("a tool definition is reused when its tool is called")
  func toolDefinitionIsJudgedByItsCall() throws {
    var capture = SessionCapture(
      session: try Self.reference("short-session"), includeSubagents: false, window: nil)
    try capture.refresh()
    let session = capture.finish()
    let lane = try #require(session.recording.mainLane)
    var judge = LexicalJudge()
    judge.add(try #require(session.judgeInputs[lane.id]))
    let findings = judge.report().bySegment()

    let tools = lane.segments.filter { $0.band == .tools || $0.band == .mcp }
    #expect(tools.count > 10)
    #expect(tools.allSatisfy { findings[$0.id]?.isAssessable == true })
    let used = tools.filter { (findings[$0.id]?.referencedShare ?? 0) > 0 }
    #expect(!used.isEmpty)
    #expect(used.count < tools.count)
    #expect(used.allSatisfy { findings[$0.id]?.referencedShare == 1 })
    let block = try #require(used.first)
    #expect(try !#require(capture.content(of: block.id)).text.isEmpty)
  }

  @Test("parsed entries are not kept once their request is processed")
  func entriesAreReleased() throws {
    var capture = SessionCapture(
      session: try Self.reference("compaction-session"), includeSubagents: false, window: nil)
    try capture.refresh()
    let session = capture.finish()
    let lane = try #require(session.recording.mainLane)
    #expect(lane.segments.count > 40)
    #expect(lane.stats.heldEntries <= EntryStore.cacheLimit)
    #expect(lane.stats.heldEntries < lane.segments.count)
    let withText = try #require(lane.segments.first { $0.characters > 0 })
    #expect(capture.content(of: withText.id) != nil)
  }

  @Test("the recorded prefix is blocks with their own text")
  func recordedPrefixBlocks() throws {
    var capture = SessionCapture(
      session: try Self.reference("short-session"), includeSubagents: false, window: nil)
    try capture.refresh()
    let lane = try #require(capture.finish().recording.mainLane)

    let system = lane.segments.filter { $0.band == .sys && $0.characters > 0 }
    #expect(system.count == 13)
    #expect(system.map(\.label) == (1...13).map { "System prompt \($0)" })
    for block in system {
      #expect(try !#require(capture.content(of: block.id)).text.isEmpty)
    }
    // The second snapshot carries the same strings.
    #expect(lane.segments.count { $0.band == .sys && $0.label == "System prompt 1" } == 1)

    let memory = lane.segments.filter { $0.band == .mem && $0.label.hasPrefix("Memory ") }
    #expect(memory.count > 1)
    #expect(Set(memory.map(\.label)).count == memory.count)
    for file in memory {
      #expect(try !#require(capture.content(of: file.id)).text.isEmpty)
    }
  }
}
