/// Assigns a size to every segment at the moment it enters the context, so
/// that the sizes of the live segments sum to the measured request total
/// exactly, at every request, by construction.
///
/// Three kinds of size go in:
///   measured  a group whose total the API reported, such as a thinking block
///             (`thinking_tokens`) or the blocks of one response
///             (`output_tokens`)
///   estimated everything the transcript only shows as text
///   derived   whatever is left over, which is how the unobserved prefix and
///             any later prefix change get their size

public struct PendingSegment: Sendable {
  public let band: Band
  public let label: String
  public let characters: Int
  public let contentClass: ContentClass
  public let contentHash: UInt64
  /// Members of the same group share one measured total.
  public let group: Int?
  public let originRequest: Int?
  /// False when the transcript only hints at what the harness injected, as
  /// with an attachment it did not record the rendering of. Such a segment
  /// still gets a size, but it never teaches the calibration anything.
  public let isReliable: Bool
  /// For the framing segment: what it is expected to cost, since it has no
  /// characters of its own to estimate from.
  public let framingAllowance: Double?
  /// The tool this block is the definition of, when it is one.
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
  /// Sizes of the segments that left the context before this request.
  public let leavingTokens: Int
  /// Measured total per group id.
  public let groupTotals: [Int: Int]
  /// Leave the estimates as they are and report any room beyond them as
  /// unallocated, instead of scaling them up to fill it.
  ///
  /// True for the first request of a lane, where the leftover is the
  /// unobserved prefix rather than an error in the estimate, and true again
  /// whenever room was freed by guessing which segments left: that guess being
  /// generous is not the entering blocks being large.
  public let absorbSurplus: Bool
  /// How far above its own estimate an entering block may be sized when room
  /// was freed by a guess. Beyond it the room is somebody else's and is
  /// reported as such. Nil means no cap, which is what a request nobody
  /// guessed about gets.
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
  /// Measured group totals the sizer refused, because they cannot be right
  /// for the content they would have to cover.
  public var rejectedGroups: Int = 0

  /// One per entering segment, in the same order.
  public let tokens: [Tokens]
  /// Tokens the entering segments did not account for. The caller turns this
  /// into the prefix, or into a prefix change.
  public let unallocated: Int
  /// How far the estimate was off before normalization, in tokens. Positive
  /// means it estimated too much.
  public let residualTokens: Int
  /// Tokens that entered the context at this request.
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

  /// What the harness is expected to have injected at a request, as a segment
  /// the caller can put in the context. It is real: the model read it. It is
  /// simply not in the transcript, so it is named and graded rather than
  /// folded into whatever block happened to arrive with it.
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

    // A measured number that cannot be right is not evidence. Some subagent
    // transcripts report an `output_tokens` of one for a response carrying
    // 300 characters across two blocks: 30 of 61 requests in one lane. Taken
    // at face value that pins real blocks at the floor and hides them.
    var rejected = 0
    for (group, indices) in grouped {
      guard let total = request.groupTotals[group] else { continue }
      let expected = indices.reduce(0.0) { sum, index in
        let segment = request.entering[index]
        return sum
          + rates.estimate(characters: segment.characters, contentClass: segment.contentClass)
      }
      // Too small to give every block a token, or smaller than the estimate
      // by more than a factor of four.
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
      // The estimate stands and the leftover is somebody else's: the
      // unobserved prefix at the first request, and whatever a retirement
      // freed beyond what was needed at any later one.
      var estimated = 0
      for (slot, index) in estimatedIndices.enumerated() {
        tokens[index] = max(1, Int(estimates[slot].rounded()))
        estimated += tokens[index]
      }
      unallocated = max(0, remaining - estimated)
    } else if estimatedIndices.isEmpty {
      if remaining < 0 {
        // Nothing to estimate and the measured groups overshoot: take the
        // difference off the groups so the request total stays exact.
        shrinkGroups(&tokens, grouped: grouped, by: -remaining)
      } else {
        unallocated = remaining
      }
    } else if remaining < estimatedIndices.count {
      // The measured groups leave less than a token per entering block. Give
      // every block its floor and take the difference off the groups, which
      // is where the slack is.
      for index in estimatedIndices { tokens[index] = 1 }
      residualTokens = Int(estimateSum.rounded()) - remaining
      var left = shrinkGroups(&tokens, grouped: grouped, by: estimatedIndices.count - remaining)
      // Nothing left to take: a request whose whole delta is smaller than the
      // number of blocks that entered. The total stays exact and some blocks
      // end up at zero, which is the truth about them.
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
        // Room freed by a guess about which segments left must not become the
        // size of whatever happened to enter. A 1,982 character input sized at
        // 7,861 tokens is the guess being generous, not the input being large.
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

  /// A sample only teaches the calibration when it is worth learning from:
  /// big enough for the relative fit to mean something, and made only of
  /// content the transcript recorded in full.
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
