/// What each block cost so far: the exact cost of every request, attributed
/// to the blocks in it by size.
///
/// A block is billed at the write price at a request where its tokens were
/// written to the cache, and at the read price everywhere else it was in the
/// context. Which of the two it was is decided by `SegmentCacheAnalysis`, the
/// one place that knows where the read prefix of a request ends in reading
/// order, so this and the cache view can never disagree about a block.
///
/// It is an attribution and carries the block's grade: a block whose size is
/// estimated has an estimated cost. The attributions of a request do not add
/// up to its exact cost to the cent, because tokens no block accounts for and
/// the few uncached tokens at the end of a prompt are billed but belong to no
/// block.

public struct BlockCost: Sendable, Codable, Hashable {
  public let segment: SegmentID
  /// Requests the block has been in, up to and including the one asked about.
  public let requestsIn: Int
  /// Of those, the requests where its tokens were written to the cache.
  public let writes: Int
  /// And the ones where they were read out of it.
  public var reads: Int { requestsIn - writes }
  /// Dollars so far: tokens times, per request, the write or the read price.
  public let dollars: Double
  /// What the block costs to send once more from the cache at the prices of
  /// the request asked about. The "per request" beside the cost so far.
  public let perRequest: Double
  /// The grade of the size the attribution rests on.
  public let grade: Grade
}

public struct BlockCostAnalysis: Sendable {
  /// The request the costs are as of.
  public let request: Int
  /// One per segment of the lane, in the lane's order. A block not yet born
  /// at `request` has been in no request and costs nothing.
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
  /// Costs of every block as of `request`, the playhead.
  ///
  /// Linear in blocks plus requests: prices are summed once as a running sum
  /// over requests, so a block's read cost is a difference of two sums, and
  /// only the requests that wrote something old again are visited per block.
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

    // Dollars per token read from the start through each request.
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
