public struct SegmentCost: Sendable, Codable, Hashable {
  public let segment: SegmentID
  public let band: Band
  public let label: String
  public let tokens: Tokens
  public let requestsCarried: Int
  public let carryTokens: Tokens
  public let unreferencedCarryTokens: Tokens?
  public let referencedShare: Double?
  public let isAssessable: Bool
  public let unreferencedAge: Int
}

public struct CarryCostAnalysis: Sendable, Codable {
  public let ranked: [SegmentCost]
  public let totalCarryTokens: Tokens
  public let maxUnreferencedAge: Int
  public let maxUnreferencedAgeSegment: SegmentID?

  public func top(_ count: Int = 6) -> [SegmentCost] {
    Array(ranked.prefix(count))
  }
}

public enum CarryCostAnalyzer {
  public static func top(
    _ lane: Lane,
    references: ReferenceReport?,
    upTo request: Int,
    count: Int
  ) -> [SegmentCost] {
    var findings: [SegmentID: ReferenceFinding] = [:]
    for finding in references?.findings ?? [] { findings[finding.segment] = finding }
    var best: [SegmentCost] = []
    for segment in lane.segments where segment.isLive(at: request) {
      let finding = findings[segment.id]
      guard finding?.isAssessable ?? segment.isAssessable else { continue }
      let share = finding?.referencedShare ?? 0
      let carried = requestsCarried(of: segment, upTo: request)
      let unreferenced = Int(Double(segment.tokens.value * carried) * (1 - share))
      guard unreferenced > 0 else { continue }
      guard best.count < count || unreferenced > (best.last?.unreferencedCarryTokens?.value ?? 0)
      else { continue }
      let cost = SegmentCost(
        segment: segment.id,
        band: segment.band,
        label: segment.label,
        tokens: segment.tokens,
        requestsCarried: carried,
        carryTokens: carry(of: segment, upTo: request),
        unreferencedCarryTokens: Tokens(unreferenced, .estimated),
        referencedShare: share,
        isAssessable: true,
        unreferencedAge: finding?.firstReference.map {
          max(0, min($0, request) - segment.born)
        } ?? carried
      )
      let slot =
        best.firstIndex { ($0.unreferencedCarryTokens?.value ?? 0) < unreferenced } ?? best.count
      best.insert(cost, at: slot)
      if best.count > count { best.removeLast() }
    }
    return best
  }

  /// Excludes `request`: a block born at 4 has been carried 0 times at 4, once at 5.
  public static func requestsCarried(of segment: Segment, upTo request: Int) -> Int {
    let died = segment.died ?? Int.max
    return max(0, min(request, died) - segment.born)
  }

  /// One more than `requestsCarried` for a live segment: the first send counts here.
  public static func requestsIn(of segment: Segment, through request: Int) -> Int {
    let died = segment.died ?? Int.max
    return max(0, min(request + 1, died) - segment.born)
  }

  public static func carry(of segment: Segment, upTo request: Int) -> Tokens {
    Tokens(segment.tokens.value * requestsCarried(of: segment, upTo: request), segment.tokens.grade)
  }

  public static func run(
    _ lane: Lane,
    references: ReferenceReport?,
    upTo request: Int? = nil,
    liveOnly: Bool = false
  ) -> CarryCostAnalysis {
    var bySegment: [SegmentID: ReferenceFinding] = [:]
    for finding in references?.findings ?? [] { bySegment[finding.segment] = finding }

    let end = min(request ?? lane.snapshots.count, lane.snapshots.count)
    var costs: [SegmentCost] = []
    costs.reserveCapacity(lane.segments.count)
    var total = 0
    var totalGrade = Grade.measured
    var maxAge = 0
    var maxAgeSegment: SegmentID?

    for segment in lane.segments {
      if liveOnly, !segment.isLive(at: end) { continue }
      let carried = requestsCarried(of: segment, upTo: end)
      let died = min(segment.died ?? end, end)
      let carry = segment.tokens.value * carried
      total += carry
      totalGrade = max(totalGrade, segment.tokens.grade)
      let finding = bySegment[segment.id]
      let assessable = finding?.isAssessable ?? segment.isAssessable
      let share = finding?.referencedShare
      let unreferenced =
        assessable
        ? Tokens(Int(Double(carry) * (1 - (share ?? 0))), .estimated) : nil
      let unreferencedAge: Int
      if let first = finding?.firstReference {
        unreferencedAge = max(0, min(first, died) - segment.born)
      } else {
        unreferencedAge = carried
      }
      if assessable, (share ?? 0) == 0, unreferencedAge > maxAge {
        maxAge = unreferencedAge
        maxAgeSegment = segment.id
      }
      costs.append(
        SegmentCost(
          segment: segment.id,
          band: segment.band,
          label: segment.label,
          tokens: segment.tokens,
          requestsCarried: carried,
          carryTokens: Tokens(carry, segment.tokens.grade),
          unreferencedCarryTokens: unreferenced,
          referencedShare: share,
          isAssessable: assessable,
          unreferencedAge: unreferencedAge
        )
      )
    }

    costs.sort {
      switch ($0.unreferencedCarryTokens, $1.unreferencedCarryTokens) {
      case (let left?, let right?):
        left.value == right.value ? $0.segment < $1.segment : left.value > right.value
      case (nil, _?): false
      case (_?, nil): true
      case (nil, nil):
        $0.carryTokens.value == $1.carryTokens.value
          ? $0.segment < $1.segment : $0.carryTokens.value > $1.carryTokens.value
      }
    }
    return CarryCostAnalysis(
      ranked: costs,
      totalCarryTokens: Tokens(total, totalGrade),
      maxUnreferencedAge: maxAge,
      maxUnreferencedAgeSegment: maxAgeSegment
    )
  }
}
