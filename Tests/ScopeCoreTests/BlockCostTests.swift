import Testing

@testable import ScopeCore

@Suite("Block cost")
struct BlockCostTests {
  private static func segment(
    _ id: Int, _ band: Band, _ tokens: Int, born: Int, died: Int? = nil
  ) -> Segment {
    Segment(
      id: SegmentID(id), band: band, label: "\(band.rawValue) \(id)",
      tokens: Tokens(tokens, .estimated), characters: tokens * 3, contentClass: .prose,
      born: born, died: died, contentHash: UInt64(id))
  }

  private static func snapshot(_ index: Int, read: Int, written: Int) -> Snapshot {
    Snapshot(
      index: index, requestID: nil, timestamp: Double(index), model: "m",
      usage: RequestUsage(cacheReadTokens: read, cacheCreationTokens: written))
  }

  private static let broken = Lane(
    id: .main, window: .given(200_000),
    segments: [segment(0, .sys, 1000, born: 0), segment(1, .user, 100, born: 1)],
    snapshots: [
      snapshot(0, read: 0, written: 1000),
      snapshot(1, read: 1000, written: 100),
      snapshot(2, read: 0, written: 1100),
    ])

  private static func costs(_ lane: Lane, at request: Int) -> BlockCostAnalysis {
    BlockCostAnalyzer.run(
      lane, cache: SegmentCacheAnalyzer.run(lane), costs: CostAnalyzer.run(lane),
      upTo: request)
  }

  @Test("a block pays the write price where it was written and the read price elsewhere")
  func writtenAndRead() throws {
    let before = Self.costs(Self.broken, at: 1)
    let prefix = try #require(before.cost(of: SegmentID(0)))
    #expect(prefix.requestsIn == 2)
    #expect(prefix.writes == 1)
    #expect(prefix.reads == 1)
    #expect(abs(prefix.dollars - 1000 * (20 + 0.25) / 1_000_000) < 1e-12)
    let prompt = try #require(before.cost(of: SegmentID(1)))
    #expect(prompt.requestsIn == 1)
    #expect(abs(prompt.dollars - 100 * 20 / 1_000_000) < 1e-12)
    #expect(abs(prompt.perRequest - 100 * 0.25 / 1_000_000) < 1e-12)
    #expect(prompt.grade == .estimated)
  }

  @Test("a cache break writes every block past the read boundary again")
  func rewritten() throws {
    let after = Self.costs(Self.broken, at: 2)
    let prefix = try #require(after.cost(of: SegmentID(0)))
    #expect(prefix.writes == 2)
    #expect(abs(prefix.dollars - 1000 * (20 + 0.25 + 20) / 1_000_000) < 1e-12)
    let prompt = try #require(after.cost(of: SegmentID(1)))
    #expect(prompt.writes == 2)
    #expect(abs(prompt.dollars - 100 * 40 / 1_000_000) < 1e-12)
  }

  @Test("a block that left stops costing, and one not yet born costs nothing")
  func lifetime() throws {
    let lane = Lane(
      id: .main, window: .given(200_000),
      segments: [
        Self.segment(0, .sys, 1000, born: 0),
        Self.segment(1, .read, 500, born: 0, died: 1),
        Self.segment(2, .asst, 50, born: 2),
      ],
      snapshots: [
        Self.snapshot(0, read: 0, written: 1500),
        Self.snapshot(1, read: 1000, written: 0),
        Self.snapshot(2, read: 1000, written: 50),
      ])
    let at1 = Self.costs(lane, at: 1)
    #expect(at1.cost(of: SegmentID(1))?.requestsIn == 1)
    #expect(at1.cost(of: SegmentID(1))?.perRequest == 0)
    #expect(at1.cost(of: SegmentID(2))?.requestsIn == 0)
    #expect(at1.cost(of: SegmentID(2))?.dollars == 0)
    let at2 = Self.costs(lane, at: 2)
    #expect(at2.cost(of: SegmentID(1))?.dollars == at1.cost(of: SegmentID(1))?.dollars)
  }

  @Test("an empty lane and a one request lane are answered without a crash")
  func edges() {
    let empty = Lane(id: .main, window: .given(200_000), segments: [], snapshots: [])
    #expect(Self.costs(empty, at: 0).perSegment.isEmpty)
    let one = SyntheticRecording.make(.oneRequest).mainLane!
    let costs = Self.costs(one, at: 0)
    #expect(costs.perSegment.allSatisfy { $0.writes == $0.requestsIn })
    let exact = CostAnalyzer.run(one).perRequest[0].context
    let attributed = costs.perSegment.reduce(0) { $0 + $1.dollars }
    #expect(abs(attributed - exact) < 1e-9)
  }

  @Test("on a lane whose blocks sum to every total, the attribution sums to the exact cost")
  func sumsToExact() {
    let lane = SyntheticRecording.make().mainLane!
    let exact = CostAnalyzer.run(lane)
    for request in [0, 10, 30, 44, lane.snapshots.count - 1] {
      let attributed = Self.costs(lane, at: request).perSegment.reduce(0) { $0 + $1.dollars }
      #expect(abs(attributed - exact.context(through: request)) < 1e-6)
    }
  }
}
