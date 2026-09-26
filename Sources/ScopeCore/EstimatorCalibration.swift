public struct EstimatorCalibration: Sendable, Codable {
  /// Per-block cost is fixed, not a column: it is collinear with the per-request term.
  private static let dimension = ContentClass.allCases.count + 1
  /// Small enough that a few hundred samples win, large enough that five cannot invent a rate.
  private static let ridge = 8.0

  private var normal: [Double]
  private var right: [Double]
  private var count = 0

  public init() {
    normal = [Double](repeating: 0, count: Self.dimension * Self.dimension)
    right = [Double](repeating: 0, count: Self.dimension)
  }

  public var sampleCount: Int { count }

  public mutating func merge(_ other: EstimatorCalibration) {
    for index in normal.indices { normal[index] += other.normal[index] }
    for index in right.indices { right[index] += other.right[index] }
    count += other.count
  }

  /// Weighted for relative error, so a large request does not drown out a small one.
  public mutating func observe(_ sample: EstimatorSample) {
    guard sample.tokens > 0 else { return }
    let row = Self.row(of: sample)
    let target = Double(sample.tokens) - EstimatorRates.tokensPerBlock * Double(sample.blocks)
    guard target > 0 else { return }
    let weight = 1.0 / (Double(sample.tokens) * Double(sample.tokens))
    for i in 0..<Self.dimension {
      for j in 0..<Self.dimension {
        normal[i * Self.dimension + j] += weight * row[i] * row[j]
      }
      right[i] += weight * row[i] * target
    }
    count += 1
  }

  public func rates(prior: EstimatorRates = .prior) -> EstimatorRates {
    guard count > 0 else { return prior }
    let priorVector = Self.vector(of: prior)
    var matrix = normal
    var vector = right
    for i in 0..<Self.dimension {
      // Ridge in relative units so every class is pulled equally hard.
      let scale = Self.ridge / (priorVector[i] * priorVector[i])
      matrix[i * Self.dimension + i] += scale
      vector[i] += scale * priorVector[i]
    }
    guard let solution = Self.solve(matrix, vector) else { return prior }
    var rates = prior
    for (index, contentClass) in ContentClass.allCases.enumerated() {
      let value = solution[index]
      let bound = priorVector[index]
      rates.tokensPerCharacter[contentClass] = min(max(value, bound / 3), bound * 3)
    }
    let framingPrior = priorVector[Self.dimension - 1]
    rates.tokensPerRequest = min(
      max(solution[Self.dimension - 1], 0), framingPrior * 3)
    rates.samples = count
    return rates
  }

  private static func row(of sample: EstimatorSample) -> [Double] {
    var row = [Double](repeating: 0, count: dimension)
    for (index, contentClass) in ContentClass.allCases.enumerated() {
      row[index] = Double(sample.characters[contentClass] ?? 0)
    }
    row[dimension - 1] = 1
    return row
  }

  private static func vector(of rates: EstimatorRates) -> [Double] {
    var vector = [Double](repeating: 0, count: dimension)
    for (index, contentClass) in ContentClass.allCases.enumerated() {
      vector[index] = rates.rate(for: contentClass)
    }
    vector[dimension - 1] = max(rates.tokensPerRequest, 1)
    return vector
  }

  private static func solve(_ matrix: [Double], _ vector: [Double]) -> [Double]? {
    let n = dimension
    var a = matrix
    var b = vector
    for column in 0..<n {
      var pivot = column
      for row in (column + 1)..<n where abs(a[row * n + column]) > abs(a[pivot * n + column]) {
        pivot = row
      }
      guard abs(a[pivot * n + column]) > 1e-12 else { return nil }
      if pivot != column {
        for k in 0..<n { a.swapAt(column * n + k, pivot * n + k) }
        b.swapAt(column, pivot)
      }
      for row in (column + 1)..<n {
        let factor = a[row * n + column] / a[column * n + column]
        guard factor != 0 else { continue }
        for k in column..<n { a[row * n + k] -= factor * a[column * n + k] }
        b[row] -= factor * b[column]
      }
    }
    var solution = [Double](repeating: 0, count: n)
    for row in stride(from: n - 1, through: 0, by: -1) {
      var value = b[row]
      for k in (row + 1)..<n { value -= a[row * n + k] * solution[k] }
      solution[row] = value / a[row * n + row]
    }
    return solution.allSatisfy { $0.isFinite } ? solution : nil
  }
}
