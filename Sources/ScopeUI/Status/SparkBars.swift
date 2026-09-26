public struct SparkBar: Sendable, Equatable {
  public let height: Double
  public let isBreak: Bool

  public init(height: Double, isBreak: Bool) {
    self.height = height
    self.isBreak = isBreak
  }
}

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
