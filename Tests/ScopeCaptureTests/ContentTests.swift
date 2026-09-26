import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture

/// The sidebar's text box needs a segment's text, and nothing may hold it
/// between requests. These are the tests for both halves of that.
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
    // Every segment that stands for recorded text can be read back. The ones
    // that cannot are the derived prefix and the framing, which have none.
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
    // A tool definition is judged by its call, not by its words, so its one
    // shingle is not a shingle of its text. Every other segment's is.
    let byID = Dictionary(
      lane.segments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var checked = 0
    for judged in input.segments where !judged.shingles.isEmpty {
      guard let segment = byID[judged.id],
        segment.band != .tools, segment.band != .mcp,
        let content = capture.content(of: judged.id)
      else { continue }
      let all = Set(Shingler.shingles(of: content.text))
      // The adapter samples at most a few hundred shingles of a segment, so
      // what the judge holds is a subset of what the text yields.
      #expect(Set(judged.shingles).isSubset(of: all))
      checked += 1
      if checked > 40 { break }
    }
    #expect(checked > 0)
  }

  /// A tool schema is referenced when the tool is called.
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
    // Every one of them can be assessed now that it has a name, which is what
    // the band could never do while it was a share of a number.
    #expect(tools.allSatisfy { findings[$0.id]?.isAssessable == true })
    // The session called some of its tools and not others, and the two read
    // differently.
    let used = tools.filter { (findings[$0.id]?.referencedShare ?? 0) > 0 }
    #expect(!used.isEmpty)
    #expect(used.count < tools.count)
    #expect(used.allSatisfy { findings[$0.id]?.referencedShare == 1 })
    // And the block's text is the definition, which a reader can show.
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
    // Whatever the file holds, what stays resident is bounded by the cache,
    // and the content still comes back.
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

    // One block per string of the recorded system prompt, each readable.
    let system = lane.segments.filter { $0.band == .sys && $0.characters > 0 }
    #expect(system.count == 13)
    #expect(system.map(\.label) == (1...13).map { "System prompt \($0)" })
    for block in system {
      #expect(try !#require(capture.content(of: block.id)).text.isEmpty)
    }
    // The second snapshot carries the same strings and must not put them in
    // the context a second time.
    #expect(lane.segments.count { $0.band == .sys && $0.label == "System prompt 1" } == 1)

    // One block per memory file, named after the file. The rest of the MEM
    // band is the session context and the output style, which are one
    // injection each and stay one block each.
    let memory = lane.segments.filter { $0.band == .mem && $0.label.hasPrefix("Memory ") }
    #expect(memory.count > 1)
    #expect(Set(memory.map(\.label)).count == memory.count)
    for file in memory {
      #expect(try !#require(capture.content(of: file.id)).text.isEmpty)
    }
  }
}
