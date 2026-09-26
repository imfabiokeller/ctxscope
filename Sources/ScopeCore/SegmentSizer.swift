public struct PendingSegment: Sendable {
  public let band: Band
  public let label: String
  public let characters: Int
  public let contentClass: ContentClass
  public let contentHash: UInt64
  public let group: Int?
  public let originRequest: Int?
  public let isReliable: Bool
  public let framingAllowance: Double?
  public let toolName: String?

  public init(
    band: Band,
    label: String,
    characters: Int,
    contentClass: ContentClass,
    contentHash: UInt64,
    group: Int? = nil,
    originRequest: Int? = nil,
    isReliable: Bool = true,
    framingAllowance: Double? = nil,
    toolName: String? = nil
  ) {
    self.band = band
    self.label = label
    self.characters = characters
    self.contentClass = contentClass
    self.contentHash = contentHash
    self.group = group
    self.originRequest = originRequest
    self.isReliable = isReliable
    self.framingAllowance = framingAllowance
    self.toolName = toolName
  }
}

public struct SizingRequest: Sendable {
  public let measuredTotal: Int
  public let entering: [PendingSegment]
  public let leavingTokens: Int
  public let groupTotals: [Int: Int]
  /// Keep the estimates and report leftover room as unallocated instead of scaling them up.
  public let absorbSurplus: Bool
  public let estimateTolerance: Double?

  public init(
    measuredTotal: Int,
    entering: [PendingSegment],
    leavingTokens: Int,
    groupTotals: [Int: Int],
    absorbSurplus: Bool,
    estimateTolerance: Double? = nil
  ) {
    self.measuredTotal = measuredTotal
    self.entering = entering
    self.leavingTokens = leavingTokens
    self.groupTotals = groupTotals
    self.absorbSurplus = absorbSurplus
    self.estimateTolerance = estimateTolerance
  }
}

public struct SizingResult: Sendable {
  public var rejectedGroups: Int = 0

  public let tokens: [Tokens]
  public let unallocated: Int
  public let residualTokens: Int
  public let appendedTokens: Int

  public init(
    tokens: [Tokens],
    unallocated: Int,
    residualTokens: Int,
    appendedTokens: Int,
    rejectedGroups: Int = 0
  ) {
    self.tokens = tokens
    self.unallocated = unallocated
    self.residualTokens = residualTokens
    self.appendedTokens = appendedTokens
    self.rejectedGroups = rejectedGroups
  }
}

public struct SegmentSizer: Sendable {
  private var carried = 0
  public private(set) var calibration = EstimatorCalibration()
  public private(set) var rates: EstimatorRates = .prior

  public init() {}

  public var carriedTokens: Int { carried }

  public var framingEstimate: Double { rates.tokensPerRequest }

  public mutating func size(_ request: SizingRequest) -> SizingResult {
    carried = max(0, carried - request.leavingTokens)
    let target = max(0, request.measuredTotal - carried)

    var tokens = [Int](repeating: 0, count: request.entering.count)
    var estimatedIndices: [Int] = []
    var grouped: [Int: [Int]] = [:]
    for (index, segment) in request.entering.enumerated() {
      if let group = segment.group, request.groupTotals[group] != nil {
        grouped[group, default: []].append(index)
      } else {
        estimatedIndices.append(index)
      }
    }

    // Some subagent transcripts report `output_tokens` of 1 for multi-block responses.
    // A total that cannot be right is not evidence.
    var rejected = 0
    for (group, indices) in grouped {
      guard let total = request.groupTotals[group] else { continue }
      let expected = indices.reduce(0.0) { sum, index in
        let segment = request.entering[index]
        return sum
          + rates.estimate(characters: segment.characters, contentClass: segment.contentClass)
      }
      guard total < indices.count || Double(total) * 4 < expected else { continue }
      grouped[group] = nil
      estimatedIndices.append(contentsOf: indices)
      rejected += 1
    }
    estimatedIndices.sort()

    var measuredSum = 0
    for (group, indices) in grouped {
      let total = request.groupTotals[group] ?? 0
      let weights = indices.map { Double(max(1, request.entering[$0].characters)) }
      let parts = Normalizer.allocate(total: total, weights: weights)
      for (slot, index) in indices.enumerated() { tokens[index] = parts[slot] }
      measuredSum += total
    }

    let estimates = estimatedIndices.map { index -> Double in
      let segment = request.entering[index]
      if let allowance = segment.framingAllowance { return allowance }
      return rates.estimate(characters: segment.characters, contentClass: segment.contentClass)
    }
    let estimateSum = estimates.reduce(0, +)
    let remaining = target - measuredSum

    var residualTokens = 0
    var unallocated = 0

    if request.absorbSurplus, remaining >= Int(estimateSum.rounded()),
      !estimatedIndices.isEmpty
    {
      var estimated = 0
      for (slot, index) in estimatedIndices.enumerated() {
        tokens[index] = max(1, Int(estimates[slot].rounded()))
        estimated += tokens[index]
      }
      unallocated = max(0, remaining - estimated)
    } else if estimatedIndices.isEmpty {
      if remaining < 0 {
        shrinkGroups(&tokens, grouped: grouped, by: -remaining)
      } else {
        unallocated = remaining
      }
    } else if remaining < estimatedIndices.count {
      for index in estimatedIndices { tokens[index] = 1 }
      residualTokens = Int(estimateSum.rounded()) - remaining
      var left = shrinkGroups(&tokens, grouped: grouped, by: estimatedIndices.count - remaining)
      // Some blocks end at zero here; the request total stays exact.
      for index in estimatedIndices where left > 0 {
        let take = min(left, tokens[index])
        tokens[index] -= take
        left -= take
      }
    } else {
      residualTokens = Int((estimateSum - Double(remaining)).rounded())
      let parts = Normalizer.allocate(total: remaining, weights: estimates)
      for (slot, index) in estimatedIndices.enumerated() { tokens[index] = parts[slot] }
      if let tolerance = request.estimateTolerance {
        // Room freed by a guessed retirement must not become the size of whatever entered.
        var spare = 0
        for (slot, index) in estimatedIndices.enumerated() {
          let cap = max(1, Int((estimates[slot] * tolerance).rounded()))
          guard tokens[index] > cap else { continue }
          spare += tokens[index] - cap
          tokens[index] = cap
        }
        unallocated = spare
      } else {
        observe(request: request, indices: estimatedIndices, tokens: remaining)
      }
    }

    carried += tokens.reduce(0, +) + unallocated
    return SizingResult(
      tokens: graded(tokens, request: request, grouped: grouped),
      unallocated: unallocated,
      residualTokens: residualTokens,
      appendedTokens: target,
      rejectedGroups: rejected
    )
  }

  /// Smaller samples are too small for the relative fit to mean anything.
  private static let minimumSample = 300

  private mutating func observe(request: SizingRequest, indices: [Int], tokens: Int) {
    guard tokens >= Self.minimumSample else { return }
    guard indices.allSatisfy({ request.entering[$0].isReliable }) else { return }
    var characters: [ContentClass: Int] = [:]
    for index in indices {
      let segment = request.entering[index]
      characters[segment.contentClass, default: 0] += segment.characters
    }
    calibration.observe(
      EstimatorSample(characters: characters, blocks: indices.count, tokens: tokens)
    )
    rates = calibration.rates()
  }
}
