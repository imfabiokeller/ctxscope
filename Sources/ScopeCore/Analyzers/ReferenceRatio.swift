public struct ReferenceSummary: Sendable, Codable, Hashable {
  public let request: Int
  public let totalTokens: Tokens
  public let assessedTokens: Tokens
  public let notAssessableTokens: Tokens
  public let referencedTokens: Tokens
  public let ratio: Double
  public let interval: ClosedRange<Double>
  public let effectiveSampleSize: Double
  public let inputAssessedTokens: Tokens
  public let inputReferencedTokens: Tokens
  public let inputRatio: Double
  public var reusedShareOfContext: Double {
    let total = totalTokens.value
    guard total > 0 else { return 0 }
    return Double(referencedTokens.value) / Double(total)
  }

  public var intervalCovers: String { "sampling across segments, not judge error" }
  public let positionalShare: [Double]
}

public enum ReferenceAnalyzer {
  /// z for a two-sided 90 percent interval.
  private static let z = 1.6449

  public static func run(
    _ lane: Lane,
    references: ReferenceReport,
    at request: Int,
    order: [Segment]? = nil
  ) -> ReferenceSummary {
    var bySegment: [SegmentID: ReferenceFinding] = [:]
    for finding in references.findings { bySegment[finding.segment] = finding }
    let live = order ?? lane.promptOrderSegments(at: request)

    var total = 0
    var assessed = 0
    var notAssessable = 0
    var referenced = 0.0
    var weightSum = 0.0
    var weightSquareSum = 0.0
    var grade = Grade.measured
    var inputAssessed = 0
    var inputReferenced = 0.0
    for segment in live {
      total += segment.tokens.value
      grade = max(grade, segment.tokens.grade)
      let finding = bySegment[segment.id]
      let counts =
        (finding?.isAssessable ?? segment.isAssessable)
        && BandRegistry.countsTowardsReuseRatio(segment.band)
      if counts {
        assessed += segment.tokens.value
        let weight = Double(segment.tokens.value)
        weightSum += weight
        weightSquareSum += weight * weight
        referenced += weight * (finding?.referencedShare ?? 0)
        if segment.originRequest == nil {
          inputAssessed += segment.tokens.value
          inputReferenced += weight * (finding?.referencedShare ?? 0)
        }
      } else {
        notAssessable += segment.tokens.value
      }
    }

    let ratio = assessed > 0 ? referenced / Double(assessed) : 0
    // Kish effective sample size.
    let effective = weightSquareSum > 0 ? (weightSum * weightSum) / weightSquareSum : 0
    return ReferenceSummary(
      request: request,
      totalTokens: Tokens(total, grade),
      assessedTokens: Tokens(assessed, grade),
      notAssessableTokens: Tokens(notAssessable, grade),
      referencedTokens: Tokens(Int(referenced.rounded()), .estimated),
      ratio: ratio,
      interval: wilson(ratio: ratio, sampleSize: effective),
      effectiveSampleSize: effective,
      inputAssessedTokens: Tokens(inputAssessed, grade),
      inputReferencedTokens: Tokens(Int(inputReferenced.rounded()), .estimated),
      inputRatio: inputAssessed > 0 ? inputReferenced / Double(inputAssessed) : 0,
      positionalShare: positionalShare(live: live, findings: bySegment)
    )
  }

  private static func positionalShare(
    live: [Segment],
    findings: [SegmentID: ReferenceFinding]
  ) -> [Double] {
    let total = live.reduce(0) { $0 + $1.tokens.value }
    guard total > 0 else { return [0, 0, 0] }
    var referenced = [Double](repeating: 0, count: 3)
    var assessed = [Double](repeating: 0, count: 3)
    var position = 0
    for segment in live {
      let finding = findings[segment.id]
      let isAssessable = finding?.isAssessable ?? segment.isAssessable
      var left = segment.tokens.value
      while left > 0 {
        let third = min(2, position * 3 / total)
        let boundary = (third + 1) * total / 3
        let take = max(1, min(left, boundary - position))
        if isAssessable {
          assessed[third] += Double(take)
          referenced[third] += Double(take) * (finding?.referencedShare ?? 0)
        }
        position += take
        left -= take
      }
    }
    return (0..<3).map { assessed[$0] > 0 ? referenced[$0] / assessed[$0] : 0 }
  }

  private static func wilson(ratio: Double, sampleSize: Double) -> ClosedRange<Double> {
    guard sampleSize > 1 else { return 0...1 }
    let n = sampleSize
    let denominator = 1 + z * z / n
    let centre = (ratio + z * z / (2 * n)) / denominator
    let spread = z * ((ratio * (1 - ratio) / n + z * z / (4 * n * n)).squareRoot()) / denominator
    return max(0, centre - spread)...min(1, centre + spread)
  }
}
