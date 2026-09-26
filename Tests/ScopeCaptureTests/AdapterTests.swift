import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture

/// Fixtures are real transcripts put through `scripts/sanitize-transcript.py`: structure and
/// lengths kept, no original text.
@Suite("ClaudeCodeAdapter")
struct AdapterTests {
  static func fixture(_ name: String) throws -> [TranscriptEntry] {
    guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "jsonl")
    else {
      Issue.record("fixture \(name) is missing")
      return []
    }
    return try ClaudeCodeAdapter.entries(at: url)
  }

  static func lane(_ name: String) throws -> LaneBuilder.Output {
    var builder = LaneBuilder(id: .main, agentType: nil, parentToolUseID: nil, window: nil)
    builder.append(try fixture(name))
    return builder.finish()
  }

  @Test(
    "totals equal API usage on every request",
    arguments: [
      "short-session", "compaction-session", "subagent-lane", "parallel-calls",
    ])
  func totalsAreExact(name: String) throws {
    let output = try Self.lane(name)
    let result = Validator.run(output.lane)
    #expect(result.mismatches.isEmpty)
    #expect(result.checks.first { $0.name == "totals equal API usage" }?.passed == true)
    #expect(output.lane.snapshots.count > 5)
  }

  @Test(
    "no segment is ever negative",
    arguments: [
      "short-session", "compaction-session", "subagent-lane", "parallel-calls",
    ])
  func noNegativeSegments(name: String) throws {
    let output = try Self.lane(name)
    #expect(output.lane.segments.allSatisfy { $0.tokens.value >= 0 })
    #expect(output.lane.segments.allSatisfy { ($0.died ?? Int.max) > $0.born })
  }

  @Test("the prefix is blocks, not four numbers")
  func prefixIsDerived() throws {
    let lane = try Self.lane("short-session").lane
    let prefix = lane.segments.filter {
      $0.born == 0 && BandRegistry.family(of: $0.band) == .prefix
    }
    #expect(Set(prefix.map(\.band)) == [.sys, .tools, .mcp, .mem])
    #expect(prefix.reduce(0) { $0 + $1.tokens.value } > 10_000)
    #expect(prefix.allSatisfy { $0.tokens.grade == .estimated })
    #expect(prefix.count { $0.band == .tools } > 1)
    #expect(prefix.count { $0.band == .mcp } > 1)
    #expect(prefix.allSatisfy { $0.characters > 0 })
  }

  @Test("thinking is sized from thinking tokens, not from its summary")
  func thinkingIsMeasured() throws {
    let lane = try Self.lane("short-session").lane
    let thinking = lane.segments.filter { $0.band == .think }
    #expect(thinking.count == 13)
    #expect(lane.snapshots.filter { $0.usage.thinkingTokens > 0 }.count == 14)

    var checked = 0
    for (index, snapshot) in lane.snapshots.enumerated() where snapshot.usage.thinkingTokens > 0 {
      let entered = thinking.filter { $0.born == index + 1 && $0.originRequest == index }
      guard !entered.isEmpty else { continue }
      guard entered.allSatisfy({ $0.tokens.grade != .estimated }) else { continue }
      #expect(entered.reduce(0) { $0 + $1.tokens.value } == snapshot.usage.thinkingTokens)
      checked += 1
    }
    #expect(checked >= 3)
  }

  @Test("subagent lanes are found and linked to the call that spawned them")
  func subagentDiscovery() throws {
    // A projects folder of its own, so the test never reads this machine's sessions.
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appending(path: "ctxscope-test-\(UUID().uuidString)")
    defer { try? manager.removeItem(at: root) }
    let project = root.appending(path: "-code-app")
    let folder = project.appending(path: "session-a/subagents")
    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
    let parent = try #require(
      Bundle.module.url(forResource: "Fixtures/short-session", withExtension: "jsonl"))
    let lane = try #require(
      Bundle.module.url(forResource: "Fixtures/subagent-lane", withExtension: "jsonl"))
    try manager.copyItem(at: parent, to: project.appending(path: "session-a.jsonl"))
    try manager.copyItem(at: lane, to: folder.appending(path: "agent-a1.jsonl"))
    try Data(#"{"agentType":"Explore","toolUseId":"toolu_a1"}"#.utf8)
      .write(to: folder.appending(path: "agent-a1.meta.json"))

    let sessions = try ClaudeCodeAdapter(root: root).sessions()
    let session = try #require(sessions.first { $0.id == "session-a" })
    let subagents = try ClaudeCodeAdapter.subagents(of: session)
    #expect(subagents.count == 1)
    let reference = try #require(subagents.first)
    #expect(reference.lane.rawValue == "agent-a1")
    #expect(reference.url.pathExtension == "jsonl")
    #expect(reference.agentType == "Explore")
    #expect(reference.toolUseID == "toolu_a1")
  }

  @Test("a compaction shows up as measured metadata and as segments leaving")
  func compaction() throws {
    let lane = try Self.lane("compaction-session").lane
    #expect(lane.compactions.count == 1)
    let event = lane.compactions[0]
    #expect(event.trigger == "auto")
    #expect(event.preTokens > event.postTokens)
    #expect(lane.segments.contains { $0.died == event.atRequest })
  }

  @Test("bands cover what the harness put in the context")
  func bands() throws {
    let lane = try Self.lane("short-session").lane
    let present = Set(lane.segments.map(\.band))
    #expect(present.contains(.user))
    #expect(present.contains(.asst))
    #expect(present.contains(.call))
    #expect(present.isSubset(of: Set(BandRegistry.ordered)))
  }

  @Test("the judge gets one consumer per request and one entry per segment")
  func judgeInput() throws {
    let output = try Self.lane("short-session")
    #expect(output.judgeInput.consumers.count == output.lane.snapshots.count)
    #expect(output.judgeInput.segments.count == output.lane.segments.count)
    var judge = LexicalJudge()
    judge.add(output.judgeInput)
    let report = judge.report()
    #expect(report.findings.count == output.lane.segments.count)
  }

  @Test("labels never carry transcript text")
  func labelsAreStructural() throws {
    let lane = try Self.lane("short-session").lane
    for segment in lane.segments {
      #expect(segment.label.count < 80)
      #expect(!segment.label.contains("\n"))
    }
  }
}
