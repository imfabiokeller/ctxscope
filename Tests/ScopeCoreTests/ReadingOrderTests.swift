import Testing

@testable import ScopeCore

@Suite("Reading order")
struct ReadingOrderTests {
  @Test("a column is every live block in reading order, one slice each, end to end")
  func columns() {
    let lane = SyntheticRecording.make().mainLane!
    let order = ReadingOrder(lane)
    let tally = TallyAnalyzer.run(lane)
    #expect(order.requestCount == lane.snapshots.count)
    for request in 0..<lane.snapshots.count {
      let column = order.column(at: request)
      #expect(column.slices.map(\.segment) == lane.promptOrderSegments(at: request).map(\.id))
      var offset = 0
      for slice in column.slices {
        #expect(slice.start == offset)
        offset = slice.end
      }
      #expect(column.end == lane.snapshots[request].usage.promptTotal)
      #expect(column.prefixEnd == tally.perRequest[request].prefixTokens.value)
      #expect(column.cacheBoundary == lane.snapshots[request].usage.cacheReadTokens)
    }
  }

  @Test("the prefix comes first, and a compaction drops the conversation behind it")
  func prefixFirst() throws {
    let lane = SyntheticRecording.make().mainLane!
    let order = ReadingOrder(lane)
    let compaction = try #require(lane.compactions.first?.atRequest)
    let before = order.column(at: compaction - 1)
    let after = order.column(at: compaction)
    #expect(after.end < before.end)
    #expect(after.prefixEnd == before.prefixEnd)
    for slice in before.slices {
      let isPrefix = [Kind.system, .tools, .memory].contains(slice.kind)
      #expect(isPrefix == (slice.start < before.prefixEnd))
    }
  }

  @Test("a request the lane does not have is an empty column")
  func outOfRange() {
    let empty = Lane(id: .main, window: .given(200_000), segments: [], snapshots: [])
    #expect(ReadingOrder(empty).column(at: 0).slices.isEmpty)
    let one = SyntheticRecording.make(.oneRequest).mainLane!
    let order = ReadingOrder(one)
    #expect(order.column(at: -1).slices.isEmpty)
    #expect(order.column(at: 1).slices.isEmpty)
    #expect(order.column(at: 0).end == one.snapshots[0].usage.promptTotal)
  }

  @Test("every column of a 1M window lane can be drawn from it")
  func scale() {
    let lane = SyntheticRecording.make(.millionTokenWindow).mainLane!
    let order = ReadingOrder(lane)
    let slices = (0..<order.requestCount).reduce(0) { $0 + order.column(at: $1).slices.count }
    #expect(slices > lane.segments.count)
  }
}
