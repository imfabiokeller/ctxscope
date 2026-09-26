public struct BlockCost: Sendable, Codable, Hashable {
  public let segment: SegmentID
  public let requestsIn: Int
  public let writes: Int
  public var reads: Int { requestsIn - writes }
  public let dollars: Double
  public let perRequest: Double
  public let grade: Grade
}

public struct BlockCostAnalysis: Sendable {
  public let request: Int
  public let perSegment: [BlockCost]
  private let slots: [SegmentID: Int]

  init(request: Int, perSegment: [BlockCost]) {
    self.request = request
    self.perSegment = perSegment
    var slots: [SegmentID: Int] = [:]
    slots.reserveCapacity(perSegment.count)
    for (slot, cost) in perSegment.enumerated() { slots[cost.segment] = slot }
    self.slots = slots
  }

  public func cost(of segment: SegmentID) -> BlockCost? {
    slots[segment].map { perSegment[$0] }
  }
}

public enum BlockCostAnalyzer {
  public static func run(
    _ lane: Lane,
    cache: SegmentCacheAnalysis,
    costs: CostAnalysis,
    upTo request: Int
  ) -> BlockCostAnalysis {
    let count = min(lane.snapshots.count, costs.perRequest.count)
    guard count > 0 else {
      return BlockCostAnalysis(
        request: request,
        perSegment: lane.segments.map {
          BlockCost(
            segment: $0.id, requestsIn: 0, writes: 0, dollars: 0, perRequest: 0,
            grade: $0.tokens.grade)
        })
    }
    let at = max(0, min(request, count - 1))

    var readSum = [Double](repeating: 0, count: count)
    var running = 0.0
    for index in 0..<count {
      running += costs.perRequest[index].prices.reading(1)
      readSum[index] = running
    }
    func extra(at index: Int) -> Double {
      costs.perRequest[index].prices.rewriteExtra(1)
    }

    var rewrittenAt: [SegmentID: [Int]] = [:]
    for rewrite in cache.rewriteRequests where rewrite <= at {
      for segment in cache.rewritten[rewrite] ?? [] {
        rewrittenAt[segment, default: []].append(rewrite)
      }
    }
    let perRequestPrices = costs.perRequest[at].prices

    let perSegment = lane.segments.map { segment -> BlockCost in
      let inside = CarryCostAnalyzer.requestsIn(of: segment, through: at)
      guard inside > 0, segment.born < count else {
        return BlockCost(
          segment: segment.id, requestsIn: 0, writes: 0, dollars: 0,
          perRequest: 0, grade: segment.tokens.grade)
      }
      let first = segment.born
      let last = first + inside - 1
      var perToken = readSum[last] - (first > 0 ? readSum[first - 1] : 0)
      var writes = 0
      if cache.isWritten(segment.id, born: first, at: first) {
        writes += 1
        perToken += extra(at: first)
      }
      for rewrite in rewrittenAt[segment.id] ?? [] where rewrite > first && rewrite <= last {
        writes += 1
        perToken += extra(at: rewrite)
      }
      let tokens = segment.tokens.value
      return BlockCost(
        segment: segment.id,
        requestsIn: inside,
        writes: writes,
        dollars: Double(tokens) * perToken,
        perRequest: segment.isLive(at: at) ? perRequestPrices.reading(tokens) : 0,
        grade: segment.tokens.grade
      )
    }
    return BlockCostAnalysis(request: at, perSegment: perSegment)
  }
}
