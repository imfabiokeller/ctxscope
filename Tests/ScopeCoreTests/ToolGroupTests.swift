import Testing

@testable import ScopeCore

@Suite("Tool groups")
struct ToolGroupTests {
  private static func segment(_ id: Int, _ band: Band, _ label: String, born: Int) -> Segment {
    Segment(
      id: SegmentID(id), band: band, label: label, tokens: Tokens(100 * (id + 1), .estimated),
      characters: 300, contentClass: .json, born: born, contentHash: UInt64(id))
  }

  private static let lane = Lane(
    id: .main, window: .given(200_000),
    segments: [
      segment(0, .sys, "System prompt 1", born: 0),
      segment(1, .tools, "Bash", born: 0),
      segment(2, .mcp, "mcp__github__create_pull_request", born: 3),
      segment(3, .tools, "Read", born: 0),
      segment(4, .mcp, "mcp__claude_ai_Gmail__search", born: 0),
      segment(5, .mcp, "list_issues (github)", born: 3),
      segment(6, .mcp, "MCP schemas", born: 0),
      segment(7, .read, "Read a.swift", born: 1),
    ],
    snapshots: (0..<5).map {
      Snapshot(index: $0, requestID: nil, timestamp: 0, model: "m", usage: RequestUsage())
    })

  @Test("a label names its server the way the harness wrote it")
  func servers() {
    #expect(ToolGroupAnalyzer.server(inLabel: "mcp__github__create_pull_request") == "github")
    #expect(ToolGroupAnalyzer.server(inLabel: "mcp__claude_ai_Gmail__search") == "claude_ai_Gmail")
    #expect(ToolGroupAnalyzer.server(inLabel: "list_issues (github)") == "github")
    #expect(ToolGroupAnalyzer.server(inLabel: "mcp__broken") == nil)
    #expect(ToolGroupAnalyzer.server(inLabel: "MCP schemas") == nil)
    #expect(ToolGroupAnalyzer.server(of: Self.lane.segments[7]) == nil)
    #expect(ToolGroupAnalyzer.server(of: Self.lane.segments[1]) == .builtIn)
  }

  @Test("built-in tools come first, then each server in the order it arrived")
  func grouping() {
    let findings: [SegmentID: ReferenceFinding] = [
      SegmentID(1): ReferenceFinding(
        segment: SegmentID(1), isAssessable: true, referencedShare: 1, referenceRequests: [1],
        matchedCounts: [1], assessedShingles: 1),
      SegmentID(3): ReferenceFinding(
        segment: SegmentID(3), isAssessable: true, referencedShare: 0, referenceRequests: [],
        assessedShingles: 1),
    ]
    let early = ToolGroupAnalyzer.run(Self.lane, findings: findings, at: 2)
    #expect(early.map(\.server) == [.builtIn, .mcp("claude_ai_Gmail"), .mcp(nil)])
    #expect(early[0].definitions == 2)
    #expect(early[0].tokens.value == 200 + 400)
    #expect(early[0].called == 1)
    #expect(early[0].named == 2)
    #expect(early[1].named == 0)

    let late = ToolGroupAnalyzer.run(Self.lane, findings: findings, at: 4)
    let github = late.first { $0.server == .mcp("github") }
    #expect(github?.definitions == 2)
    #expect(github?.born == 3)
    #expect(github?.tokens.value == 300 + 600)
    #expect(late.last?.server == .mcp("github"))
  }

  @Test("a lane with no tools has no groups")
  func empty() {
    let lane = Lane(id: .main, window: .given(200_000), segments: [], snapshots: [])
    #expect(ToolGroupAnalyzer.run(lane, findings: [:], at: 0).isEmpty)
  }
}
