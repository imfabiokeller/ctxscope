import Testing

@testable import ScopeCore

@Suite("Block use")
struct BlockUseTests {
  private static func segment(_ id: Int, _ band: Band, _ tokens: Int, born: Int) -> Segment {
    Segment(
      id: SegmentID(id), band: band, label: "\(band.rawValue) \(id)",
      tokens: Tokens(tokens, .estimated), characters: tokens * 3, contentClass: .prose,
      born: born, contentHash: UInt64(id))
  }

  private static let lane = Lane(
    id: .main, window: .given(200_000),
    segments: [
      segment(0, .sys, 1000, born: 0),
      segment(1, .tools, 400, born: 0),
      segment(2, .read, 2000, born: 1),
      segment(3, .bash, 600, born: 1),
    ],
    snapshots: (0..<5).map { index in
      Snapshot(
        index: index, requestID: nil, timestamp: Double(index), model: "m",
        usage: RequestUsage(
          cacheReadTokens: index == 0 ? 0 : 4000, cacheCreationTokens: index == 0 ? 1400 : 0))
    })

  private static let findings: [SegmentID: ReferenceFinding] = [
    SegmentID(1): ReferenceFinding(
      segment: SegmentID(1), isAssessable: true, referencedShare: 1, referenceRequests: [2],
      matchedCounts: [1], assessedShingles: 1),
    SegmentID(2): ReferenceFinding(
      segment: SegmentID(2), isAssessable: true, referencedShare: 0.4, referenceRequests: [3],
      matchedCounts: [8], assessedShingles: 20),
    SegmentID(3): ReferenceFinding(
      segment: SegmentID(3), isAssessable: true, referencedShare: 0, referenceRequests: [],
      assessedShingles: 30),
  ]

  private func use(_ id: Int, at request: Int) -> BlockUse {
    UseAnalyzer.use(
      of: Self.lane.segments[id], finding: Self.findings[SegmentID(id)], at: request)
  }

  @Test("used is a function of the past: a reuse at request 3 is not seen from request 2")
  func triState() {
    #expect(use(0, at: 4) == .notTracked)
    #expect(use(1, at: 4) == .notTracked)
    #expect(use(2, at: 2) == .unused)
    #expect(use(2, at: 3) == .used)
    #expect(use(3, at: 4) == .unused)
  }

  @Test("a tool definition says whether its tool was called by then")
  func called() {
    let tool = Self.lane.segments[1]
    let finding = Self.findings[SegmentID(1)]
    #expect(UseAnalyzer.called(tool, finding: finding, at: 1) == false)
    #expect(UseAnalyzer.called(tool, finding: finding, at: 2) == true)
    #expect(UseAnalyzer.called(Self.lane.segments[2], finding: nil, at: 2) == nil)
    #expect(UseAnalyzer.called(tool, finding: nil, at: 2) == nil)
  }

  @Test("the unused part is the live unused blocks, their share and their cost so far")
  func unused() {
    let lane = Self.lane
    let costs = BlockCostAnalyzer.run(
      lane, cache: SegmentCacheAnalyzer.run(lane), costs: CostAnalyzer.run(lane), upTo: 2)
    let summary = UseAnalyzer.unused(lane, findings: Self.findings, costs: costs, at: 2)
    #expect(summary.tokens.value == 2600)
    #expect(summary.tokens.grade == .estimated)
    #expect(summary.blocks == 2)
    #expect(abs(summary.share - 2600.0 / 4000.0) < 1e-12)
    let expected = [2, 3].reduce(0.0) { $0 + (costs.cost(of: SegmentID($1))?.dollars ?? 0) }
    #expect(abs(summary.dollars - expected) < 1e-12)

    let later = UseAnalyzer.unused(lane, findings: Self.findings, costs: costs, at: 3)
    #expect(later.tokens.value == 600)
  }

  @Test("an empty lane has nothing unused")
  func empty() {
    let lane = Lane(id: .main, window: .given(200_000), segments: [], snapshots: [])
    let costs = BlockCostAnalyzer.run(
      lane, cache: SegmentCacheAnalyzer.run(lane), costs: CostAnalyzer.run(lane), upTo: 0)
    let summary = UseAnalyzer.unused(lane, findings: [:], costs: costs, at: 0)
    #expect(summary.tokens.value == 0)
    #expect(summary.share == 0)
  }
}
