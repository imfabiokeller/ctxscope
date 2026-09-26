import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture

@Suite("Fixtures")
struct FixtureTests {
  struct Pinned {
    let name: String
    let requests: Int
    let segments: Int
    let prefixTokens: Int
    let peak: Int
    let window: Int
    let toolCalls: Int
    let busts: Int
    let compactions: Int
    let inferredRetirements: Int
    let flooredSegments: Int
    let bands: [Band]
  }

  static let pinned: [Pinned] = [
    Pinned(
      name: "short-session", requests: 16, segments: 173, prefixTokens: 48_020,
      peak: 106_999, window: 200_000, toolCalls: 22, busts: 1, compactions: 0,
      inferredRetirements: 0, flooredSegments: 0,
      bands: [.sys, .tools, .mcp, .mem, .user, .asst, .think, .call, .read, .srch]),
    Pinned(
      name: "compaction-session", requests: 23, segments: 128, prefixTokens: 967_347,
      peak: 994_421, window: 1_000_000, toolCalls: 17, busts: 1, compactions: 1,
      inferredRetirements: 4, flooredSegments: 0,
      bands: [.sys, .tools, .mcp, .mem, .user, .asst, .think, .call, .bash, .agent]),
    Pinned(
      name: "subagent-lane", requests: 14, segments: 93, prefixTokens: 16_997,
      peak: 79_020, window: 200_000, toolCalls: 31, busts: 0, compactions: 0,
      inferredRetirements: 0, flooredSegments: 0,
      bands: [.sys, .tools, .mcp, .mem, .user, .asst, .think, .call, .read, .bash]),
    Pinned(
      // No session on this machine ran a 500k window; 1M is the smallest with evidence.
      name: "parallel-calls", requests: 11, segments: 99, prefixTokens: 460_098,
      peak: 498_847, window: 1_000_000, toolCalls: 21, busts: 0, compactions: 0,
      inferredRetirements: 0, flooredSegments: 0,
      bands: [.sys, .tools, .mcp, .mem, .user, .asst, .think, .call, .read, .bash, .srch]),
  ]

  @Test("a fixture produces exactly the numbers it produced before", arguments: pinned)
  func numbersAreStable(expected: Pinned) throws {
    let lane = try AdapterTests.lane(expected.name).lane
    #expect(lane.snapshots.count == expected.requests)
    #expect(lane.segments.count == expected.segments)
    #expect(
      lane.segments.filter { $0.born == 0 && $0.family == .prefix }
        .reduce(0) { $0 + $1.tokens.value } == expected.prefixTokens)
    #expect(lane.snapshots.map(\.usage.promptTotal).max() == expected.peak)
    #expect(lane.window.tokens == expected.window)
    #expect(lane.stats.toolCalls == expected.toolCalls)
    #expect(CacheAnalyzer.run(lane).busts.count == expected.busts)
    #expect(lane.compactions.count == expected.compactions)
    #expect(lane.stats.inferredRetirements == expected.inferredRetirements)
    #expect(
      lane.segments.filter { $0.characters > 0 && $0.tokens.value <= Segment.floor }.count
        == expected.flooredSegments)
    let bands = BandRegistry.ordered.filter { band in
      lane.segments.contains { $0.band == band }
    }
    #expect(bands == expected.bands)
  }

  @Test("the compaction fixture puts its boundary on the right request")
  func compactionBoundary() throws {
    let lane = try AdapterTests.lane("compaction-session").lane
    let event = try #require(lane.compactions.first)
    #expect(event.trigger == "auto")
    #expect(event.preTokens == 999_274)
    #expect(event.postTokens == 18_020)
    #expect(lane.snapshots[event.atRequest].usage.promptTotal < event.preTokens / 2)
    #expect(lane.snapshots[event.atRequest - 1].usage.promptTotal > event.preTokens / 2)
    let bust = CacheAnalyzer.run(lane).busts.first { $0.request == event.atRequest }
    #expect(bust?.cause == .compaction)
  }

  @Test("the parallel fixture has calls that share a request")
  func parallelCallsShareARequest() throws {
    let lane = try AdapterTests.lane("parallel-calls").lane
    var callsPerRequest: [Int: Int] = [:]
    for segment in lane.segments where segment.band == .call {
      callsPerRequest[segment.born, default: 0] += 1
    }
    #expect(callsPerRequest.values.contains { $0 > 1 })
    #expect(lane.stats.toolCallsWithoutResult == 0)
  }

  @Test("an output total that cannot be right is refused rather than believed")
  func implausibleTotalsAreRefused() throws {
    let lane = try AdapterTests.lane("subagent-lane").lane
    // The fixture's single digit output totals all belong to responses with no stop reason.
    #expect(lane.stats.unfinishedResponses > 0)
    #expect(lane.stats.rejectedMeasurements == 0)
    #expect(lane.segments.allSatisfy { $0.characters == 0 || $0.tokens.value > Segment.floor })
    #expect(Validator.run(lane).passed)
  }

  @Test("an empty file is a lane with nothing in it, not a crash")
  func emptyFile() throws {
    var builder = LaneBuilder(id: .main, agentType: nil, parentToolUseID: nil, window: nil)
    builder.append([])
    let output = builder.finish()
    #expect(output.lane.snapshots.isEmpty)
    #expect(output.lane.segments.isEmpty)
    #expect(Validator.run(output.lane).mismatches.isEmpty)
    #expect(TallyAnalyzer.run(output.lane).perRequest.isEmpty)
  }

  @Test("a file of nothing but unknown entry types is read without failing")
  func unknownEntriesOnly() throws {
    let entries = try ["queue-operation", "atis-latch", "something-new"].map {
      TranscriptEntry(try JSONValue(parsing: Data("{\"type\":\"\($0)\"}".utf8)))
    }
    var builder = LaneBuilder(id: .main, agentType: nil, parentToolUseID: nil, window: nil)
    builder.append(entries)
    #expect(builder.finish().lane.snapshots.isEmpty)
  }
}

extension FixtureTests.Pinned: CustomTestStringConvertible {
  var testDescription: String { name }
}
