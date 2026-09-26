import Testing

@testable import ScopeCore

@Suite("Prompt order")
struct PromptOrderTests {
  private func lane() -> Lane {
    var segments: [Segment] = []
    func add(_ band: Band, born: Int, tokens: Int) {
      segments.append(
        Segment(
          id: SegmentID(segments.count),
          band: band,
          label: band.rawValue,
          tokens: Tokens(tokens, .estimated),
          characters: tokens,
          contentClass: .prose,
          born: born,
          contentHash: UInt64(segments.count)
        ))
    }
    add(.sys, born: 0, tokens: 100)
    add(.tools, born: 0, tokens: 100)
    add(.read, born: 1, tokens: 100)
    add(.user, born: 2, tokens: 100)
    add(.read, born: 3, tokens: 100)
    let snapshots = (0...3).map {
      Snapshot(
        index: $0, requestID: nil, timestamp: 0, model: "m",
        usage: RequestUsage(cacheReadTokens: 100 * ($0 + 2)))
    }
    return Lane(
      id: .main, window: .given(200_000), segments: segments, snapshots: snapshots)
  }

  @Test("prompt order is the prefix, then the conversation as it happened")
  func order() {
    let bands = lane().promptOrderSegments(at: 3).map(\.band)
    #expect(bands == [.sys, .tools, .read, .user, .read])
  }

  @Test("band order groups by band")
  func bandOrder() {
    let bands = lane().liveSegments(at: 3).map(\.band)
    #expect(bands == [.sys, .tools, .user, .read, .read])
  }

  @Test("the two orders disagree, which is the whole point")
  func ordersDiffer() {
    let lane = lane()
    #expect(lane.promptOrderSegments(at: 3).map(\.id) != lane.liveSegments(at: 3).map(\.id))
  }
}

@Suite("Segment cache state")
struct SegmentCacheTests {
  private func cleanLane() -> Lane {
    SyntheticRecording.make().mainLane!
  }

  @Test("everything is written once when it enters")
  func writtenOnEntry() {
    let lane = cleanLane()
    let analysis = SegmentCacheAnalyzer.run(lane)
    #expect(analysis.perSegment.count == lane.segments.count)
    #expect(analysis.perSegment.allSatisfy { $0.writes >= 1 })
    for state in analysis.perSegment {
      guard let segment = lane.segments.first(where: { $0.id == state.segment }) else { continue }
      #expect(state.firstWrite == segment.born || state.writes > 1)
    }
  }

  @Test("a rewrite is found where more was written than entered")
  func rewrites() {
    let lane = cleanLane()
    let analysis = SegmentCacheAnalyzer.run(lane)
    #expect(!analysis.rewriteRequests.isEmpty)
    #expect(analysis.perSegment.contains { $0.writes > 1 })
  }

  @Test("the read boundary is the measured cache read")
  func boundary() {
    let lane = cleanLane()
    let analysis = SegmentCacheAnalyzer.run(lane)
    for (index, snapshot) in lane.snapshots.enumerated() {
      #expect(analysis.readBoundary[index] == snapshot.usage.cacheReadTokens)
    }
  }

  @Test("a segment in the read prefix reads, one past it is written")
  func perSegmentState() throws {
    let lane = cleanLane()
    let analysis = SegmentCacheAnalyzer.run(lane)
    let request = lane.snapshots.count - 1
    let order = lane.promptOrderSegments(at: request)
    let first = try #require(order.first)
    let last = try #require(order.last)
    #expect(analysis.state(of: first.id, at: request, in: lane) == .read)
    #expect(analysis.state(of: last.id, at: request, in: lane) != nil)
  }
}
