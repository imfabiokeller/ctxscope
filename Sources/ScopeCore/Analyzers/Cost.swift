/// What each request cost, exactly, from the API's own counts and the price
/// table. Nothing here is estimated: the four token counts are measured and
/// the prices are data.

public struct RequestCost: Sendable, Codable, Hashable {
  public let request: Int
  /// The prices this request was billed at, which are the ones of its model.
  public let prices: Prices
  public let readTokens: Int
  public let writtenTokens: Int
  public let uncachedTokens: Int
  public let outputTokens: Int

  /// Everything the model read for this call.
  public var contextTokens: Int { readTokens + writtenTokens + uncachedTokens }

  /// What carrying the context cost at this request: read times the read
  /// price, written times the write price, uncached times the input price.
  public var context: Double {
    prices.reading(readTokens) + prices.writing(writtenTokens)
      + prices.sendingUncached(uncachedTokens)
  }

  public var output: Double { prices.producing(outputTokens) }
  public var total: Double { context + output }

  /// The context of this request, sent once more with all of it read from the
  /// cache.
  public var readAgain: Double { prices.reading(contextTokens) }
  /// The same context sent once more with none of it in the cache.
  public var sentAgain: Double { prices.writing(contextTokens) }
}

public struct CostAnalysis: Sendable, Codable {
  public let perRequest: [RequestCost]
  /// Context cost from the first request through each request, inclusive.
  public let cumulativeContext: [Double]
  /// The same with output included.
  public let cumulativeTotal: [Double]

  /// Context cost of the session up to and including a request. Zero for a
  /// lane with no requests.
  public func context(through request: Int) -> Double {
    guard let index = clamped(request) else { return 0 }
    return cumulativeContext[index]
  }

  public func total(through request: Int) -> Double {
    guard let index = clamped(request) else { return 0 }
    return cumulativeTotal[index]
  }

  /// Context cost over a range of requests, both ends included.
  public func context(in range: ClosedRange<Int>) -> Double {
    guard let upper = clamped(range.upperBound), range.lowerBound <= upper else { return 0 }
    let before = range.lowerBound > 0 ? cumulativeContext[range.lowerBound - 1] : 0
    return cumulativeContext[upper] - before
  }

  /// What a cache break added: the tokens written again, at the difference
  /// between the write and the read price of the request it happened at.
  public func extra(of bust: CacheBust) -> Double {
    guard let index = clamped(bust.request) else { return 0 }
    return perRequest[index].prices.rewriteExtra(bust.rewrittenTokens.value)
  }

  private func clamped(_ request: Int) -> Int? {
    guard !perRequest.isEmpty, request >= 0 else { return nil }
    return min(request, perRequest.count - 1)
  }
}

public enum CostAnalyzer {
  public static func run(_ lane: Lane, prices table: PriceTable = .standard) -> CostAnalysis {
    var perRequest: [RequestCost] = []
    perRequest.reserveCapacity(lane.snapshots.count)
    var context: [Double] = []
    var total: [Double] = []
    context.reserveCapacity(lane.snapshots.count)
    total.reserveCapacity(lane.snapshots.count)
    var runningContext = 0.0
    var runningTotal = 0.0
    for snapshot in lane.snapshots {
      let usage = snapshot.usage
      let cost = RequestCost(
        request: snapshot.index,
        prices: table.prices(for: snapshot.model),
        readTokens: usage.cacheReadTokens,
        writtenTokens: usage.cacheCreationTokens,
        uncachedTokens: usage.inputTokens,
        outputTokens: usage.outputTokens
      )
      perRequest.append(cost)
      runningContext += cost.context
      runningTotal += cost.total
      context.append(runningContext)
      total.append(runningTotal)
    }
    return CostAnalysis(
      perRequest: perRequest, cumulativeContext: context, cumulativeTotal: total)
  }
}
