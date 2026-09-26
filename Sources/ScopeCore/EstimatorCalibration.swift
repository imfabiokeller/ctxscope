/// Continuous calibration of the token estimator against derived values of
/// the same lane: an estimate is corrected by what the lane measured, never
/// the other way round.
///
/// Incremental by construction: every sample folds into a small normal
/// equation system, so a growing session costs only the new deltas and a
/// 1M-token window costs the same as a short one.
public struct EstimatorCalibration: Sendable, Codable {
  /// One column per content class, plus the per-request framing constant.
  /// The per-block cost is fixed and subtracted before the fit, because the
  /// two constants are collinear and letting the fit choose between them put
  /// the framing on tiny blocks.
  private static let dimension = ContentClass.allCases.count + 1
  /// Pull toward the prior. Small enough that a few hundred samples win,
  /// large enough that five samples cannot invent a rate.
  private static let ridge = 8.0

  private var normal: [Double]
  private var right: [Double]
  private var count = 0

  public init() {
    normal = [Double](repeating: 0, count: Self.dimension * Self.dimension)
    right = [Double](repeating: 0, count: Self.dimension)
  }

  public var sampleCount: Int { count }

  /// Pools two fits. The normal equations add, which is what makes a prior
  /// fitted over many sessions reproducible from the sessions themselves.
  public mutating func merge(_ other: EstimatorCalibration) {
    for index in normal.indices { normal[index] += other.normal[index] }
    for index in right.indices { right[index] += other.right[index] }
    count += other.count
  }

  /// Folds one derived delta into the fit. Weighted for relative error, so a
  /// 400k-token request does not drown out a 400-token one.
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

  /// Rates that best explain the samples seen so far, pulled toward `prior`
  /// and clamped to a factor of three around it.
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
    // The framing constant: one per request, however many blocks arrived.
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

  /// Gaussian elimination with partial pivoting. The system is 5 by 5.
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
