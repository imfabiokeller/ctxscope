/// One bar of the popover's context-per-request chart.
public struct SparkBar: Sendable, Equatable {
  /// How tall, as a share of the window: what the request sent against what
  /// the model could take.
  public let height: Double
  /// A request that sent the cache again, drawn in its own color.
  public let isBreak: Bool

  public init(height: Double, isBreak: Bool) {
    self.height = height
    self.isBreak = isBreak
  }
}

/// The chart's bars, one per request while they fit.
///
/// A session of a few hundred requests does not fit one bar per request in
/// the popover's width, so from `capacity` requests on, neighbouring requests
/// share a bar: each bar is the last request of its run, the newest request
/// is always the last bar, and a bar is a break when any request of its run
/// was one.
public enum SparkBars {
  public static func make(
    totals: [Int], breaks: Set<Int>, window: Int, capacity: Int
  ) -> [SparkBar] {
    let window = Double(max(1, window))
    let capacity = max(1, capacity)
    let height = { (request: Int) in min(1, max(0, Double(totals[request]) / window)) }
    guard totals.count > capacity else {
      return totals.indices.map { SparkBar(height: height($0), isBreak: breaks.contains($0)) }
    }
    let count = totals.count
    return (0..<capacity).map { slot in
      let start = slot * count / capacity
      let end = (slot + 1) * count / capacity
      return SparkBar(
        height: height(end - 1),
        isBreak: (start..<end).contains { breaks.contains($0) })
    }
  }
}
