import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture

/// The figures the window shows, worked out from the sanitized fixtures and
/// pinned, so a change to any of them has to be meant.
@Suite("Window figures on fixtures")
struct FixtureFiguresTests {
  private static func analyzed(_ name: String) throws -> (Lane, [SegmentID: ReferenceFinding]) {
    let output = try AdapterTests.lane(name)
    var judge = LexicalJudge(segmentShingleCap: LaneBuilder.shingleCap)
    judge.add(output.judgeInput)
    return (output.lane, judge.report().bySegment())
  }

  @Test("tool definitions group into the built-in tools and one group per MCP server")
  func toolGroups() throws {
    let (lane, findings) = try Self.analyzed("short-session")
    let groups = ToolGroupAnalyzer.run(lane, findings: findings, at: lane.snapshots.count - 1)
    #expect(groups.first?.server == .builtIn)
    #expect(groups.first?.definitions == 17)
    #expect(groups.first?.tokens.value == 26_054)
    #expect(groups.first?.called == 5)
    #expect(groups.dropFirst().map(\.definitions) == [3, 4, 19, 1, 1, 2])
    #expect(groups.dropFirst().allSatisfy { $0.server != .builtIn && $0.server != .mcp(nil) })
    #expect(groups.contains { $0.server == .mcp("2d2179e129e4") && $0.definitions == 19 })
  }

  @Test("each fixture's cache break carries its cause, its gap and what was written again")
  func cacheBreaks() throws {
    let (short, _) = try Self.analyzed("short-session")
    let idle = try #require(CacheAnalyzer.run(short).busts.first)
    #expect(idle.request == 4)
    #expect(idle.cause == .idle)
    // Over two hours, and the system prompt and tools were still read from
    // the cache: only the conversation after them was written again.
    #expect(abs(idle.gapSeconds - 8123.12) < 0.01)
    #expect(idle.readThrough == .tools)
    #expect(idle.change == nil)

    let (compacted, _) = try Self.analyzed("compaction-session")
    let compaction = try #require(CacheAnalyzer.run(compacted).busts.first)
    #expect(compaction.request == 9)
    #expect(compaction.cause == .compaction)
    #expect(compaction.readThrough == .tools)
  }

  @Test("a real lane's tasks cover it from the first typed prompt to the end")
  func tasks() throws {
    let (lane, _) = try Self.analyzed("short-session")
    let costs = CostAnalyzer.run(lane)
    let cache = CacheAnalyzer.run(lane)
    let tasks = PromptAnalyzer.run(lane, costs: costs, cache: cache).prompts
    // Six typed prompts, two of which entered at the same request and so
    // were answered as one.
    #expect(lane.prompts.count == 6)
    #expect(tasks.count == 5)
    #expect(tasks.first?.requests.lowerBound == 0)
    #expect(tasks.last?.requests.upperBound == lane.snapshots.count - 1)
    #expect(tasks.reduce(0) { $0 + $1.requestCount } == lane.snapshots.count)
    #expect(tasks.reduce(0) { $0 + $1.cacheBreaks } == 1)
    let spent = tasks.reduce(0) { $0 + $1.cost }
    #expect(abs(spent - costs.context(through: lane.snapshots.count - 1)) < 1e-9)
    #expect(tasks.allSatisfy { $0.largestAdded != nil })
  }

  @Test("a lane without a recorded tool list has one unnamed share per band")
  func toolShares() throws {
    let (lane, findings) = try Self.analyzed("subagent-lane")
    let groups = ToolGroupAnalyzer.run(lane, findings: findings, at: lane.snapshots.count - 1)
    #expect(groups.map(\.server) == [.builtIn, .mcp(nil)])
    #expect(groups.allSatisfy { $0.named == 0 })
  }
}
