public struct RequestCost: Sendable, Codable, Hashable {
  public let request: Int
  public let prices: Prices
  public let readTokens: Int
  public let writtenTokens: Int
  public let writtenOneHourTokens: Int
  public let writtenFiveMinuteTokens: Int
  public let uncachedTokens: Int
  public let outputTokens: Int

  public var contextTokens: Int { readTokens + writtenTokens + uncachedTokens }

  /// The lifetime this request wrote at, for prices that need one; the API's default
  /// lifetime when nothing was written.
  public var writesOneHour: Bool { writtenOneHourTokens > writtenFiveMinuteTokens }

  public var context: Double {
    prices.reading(readTokens)
      + prices.writing(
        writtenTokens, oneHour: writtenOneHourTokens, fiveMinute: writtenFiveMinuteTokens)
      + prices.sendingUncached(uncachedTokens)
  }

  public var output: Double { prices.producing(outputTokens) }
  public var total: Double { context + output }

  public var readAgain: Double { prices.reading(contextTokens) }
  public var sentAgain: Double { prices.writing(contextTokens, oneHour: writesOneHour) }
}

public struct CostAnalysis: Sendable, Codable {
  public let perRequest: [RequestCost]
  public let cumulativeContext: [Double]
  public let cumulativeTotal: [Double]

  public func context(through request: Int) -> Double {
    guard let index = clamped(request) else { return 0 }
    return cumulativeContext[index]
  }

  public func total(through request: Int) -> Double {
    guard let index = clamped(request) else { return 0 }
    return cumulativeTotal[index]
  }

  public func context(in range: ClosedRange<Int>) -> Double {
    guard let upper = clamped(range.upperBound), range.lowerBound <= upper else { return 0 }
    let before = range.lowerBound > 0 ? cumulativeContext[range.lowerBound - 1] : 0
    return cumulativeContext[upper] - before
  }

  public func extra(of bust: CacheBust) -> Double {
    guard let index = clamped(bust.request) else { return 0 }
    let request = perRequest[index]
    return request.prices.rewriteExtra(bust.rewrittenTokens.value, oneHour: request.writesOneHour)
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
        writtenOneHourTokens: usage.ephemeral1hTokens,
        writtenFiveMinuteTokens: usage.ephemeral5mTokens,
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
