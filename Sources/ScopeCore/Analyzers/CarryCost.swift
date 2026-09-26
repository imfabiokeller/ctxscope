/// Carry cost: tokens times requests carried, per segment: the area a block
/// covers in the timeline. Unreferenced carry cost ranks what was carried unused.

public struct SegmentCost: Sendable, Codable, Hashable {
  public let segment: SegmentID
  public let band: Band
  public let label: String
  public let tokens: Tokens
  public let requestsCarried: Int
  /// tokens times requests carried. No better graded than the size it rests
  /// on.
  public let carryTokens: Tokens
  /// The share of `carryTokens` no later output referenced. `nil` when the
  /// segment is not assessable. Always estimated: the judge is.
  public let unreferencedCarryTokens: Tokens?
  public let referencedShare: Double?
  public let isAssessable: Bool
  /// Requests the segment was carried before its first reference, or its
  /// whole life when nothing referenced it.
  public let unreferencedAge: Int
}

public struct CarryCostAnalysis: Sendable, Codable {
  /// Every segment, ranked by unreferenced carry cost, highest first.
  /// Not assessable segments rank last.
  public let ranked: [SegmentCost]
  public let totalCarryTokens: Tokens
  public let maxUnreferencedAge: Int
  public let maxUnreferencedAgeSegment: SegmentID?

  /// The six largest, or fewer when the lane is short.
  public func top(_ count: Int = 6) -> [SegmentCost] {
    Array(ranked.prefix(count))
  }
}

public enum CarryCostAnalyzer {
  /// The `count` costliest segments alive at a request, without sorting the
  /// whole lane to find six of them.
  ///
  /// Same numbers as `run`, same conventions, selected rather than sorted: on
  /// a 7,485 segment lane the sort was most of what a frame cost.
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

  /// Requests a segment has been carried, counted up to and not including
  /// `request`.
  ///
  /// One convention, stated once: a segment born at 4 and looked at from 4 has
  /// been carried zero requests, because it has not been re-sent yet. At 5 it
  /// has been carried once. A segment that left at 9 stops counting at 9.
  public static func requestsCarried(of segment: Segment, upTo request: Int) -> Int {
    let died = segment.died ?? Int.max
    return max(0, min(request, died) - segment.born)
  }

  /// Requests a segment has been in, counted up to and including `request`.
  ///
  /// This is the "carried" a person reads beside a block: the system prompt of
  /// a lane of 87 requests, looked at from the last one, has been in 87. It is
  /// one more than `requestsCarried` for a live segment, because that one
  /// counts the times a segment was sent again, and the first send is not
  /// one of them.
  public static func requestsIn(of segment: Segment, through request: Int) -> Int {
    let died = segment.died ?? Int.max
    return max(0, min(request + 1, died) - segment.born)
  }

  /// Tokens times requests carried, at the same convention.
  public static func carry(of segment: Segment, upTo request: Int) -> Tokens {
    Tokens(segment.tokens.value * requestsCarried(of: segment, upTo: request), segment.tokens.grade)
  }

  /// The ranked list, as of a request.
  ///
  /// `upTo` is the playhead: the cost so far, not the cost of a life that has
  /// not happened yet. `liveOnly` drops what has already left the context,
  /// because a cost nobody can still act on is not what the table is for.
  /// Everything that reads this list, the CLI, the blocks table and the snapshots,
  /// comes through here, so none of them can disagree.
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
