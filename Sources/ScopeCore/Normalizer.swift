/// Estimates are normalized so segment sums equal the enclosing measured or
/// derived total exactly: an estimate may be wrong about its share, never
/// about the total.
///
/// The allocation happens once per segment, when it enters the context, so a
/// segment has one size for its whole life and every request total is exact
/// by construction.
public enum Normalizer {
  /// Splits `total` across `weights` with the largest-remainder method, so
  /// the parts are integers that sum to exactly `total`.
  ///
  /// Every part gets at least `floor`, which keeps a real block from being
  /// rounded out of existence. If the floors alone exceed the total, the
  /// parts are as close to equal as the total allows.
  public static func allocate(total: Int, weights: [Double], floor: Int = 1) -> [Int] {
    guard !weights.isEmpty else { return [] }
    guard total > 0 else { return [Int](repeating: 0, count: weights.count) }

    let minimum = min(floor, max(0, total / weights.count))
    let reserved = minimum * weights.count
    let free = total - reserved
    guard free >= 0 else {
      return equalSplit(total: total, count: weights.count)
    }

    let sum = weights.reduce(0, +)
    guard sum > 0 else {
      let split = equalSplit(total: free, count: weights.count)
      return split.map { $0 + minimum }
    }

    var parts = [Int](repeating: minimum, count: weights.count)
    var remainders: [(index: Int, remainder: Double)] = []
    var assigned = 0
    for (index, weight) in weights.enumerated() {
      let exact = Double(free) * max(0, weight) / sum
      let whole = Int(exact)
      parts[index] += whole
      assigned += whole
      remainders.append((index, exact - Double(whole)))
    }
    var left = free - assigned
    remainders.sort { $0.remainder > $1.remainder }
    var cursor = 0
    while left > 0 && !remainders.isEmpty {
      parts[remainders[cursor % remainders.count].index] += 1
      left -= 1
      cursor += 1
    }
    return parts
  }

  private static func equalSplit(total: Int, count: Int) -> [Int] {
    guard count > 0 else { return [] }
    let base = total / count
    var parts = [Int](repeating: base, count: count)
    var left = total - base * count
    var index = 0
    while left > 0 {
      parts[index] += 1
      left -= 1
      index = (index + 1) % count
    }
    return parts
  }
}
