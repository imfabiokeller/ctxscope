/// Segments with identical content alive at the same time. The hash is
/// measured, the grouping is exact.

public struct DuplicateGroup: Sendable, Codable, Hashable {
  public let contentHash: UInt64
  public let segments: [SegmentID]
  public let label: String
  /// The size of each copy. Copies of the same content can differ in size,
  /// because each was sized against the delta it entered in, so this is a
  /// list rather than one number.
  public let copyTokens: [Tokens]
  /// What the copies beyond the first cost, summed over the requests they
  /// overlapped in.
  public let wastedCarryTokens: Tokens
  /// First request where more than one copy was alive.
  public let firstOverlap: Int
}

public struct DuplicationAnalysis: Sendable, Codable {
  public let groups: [DuplicateGroup]
  public let wastedCarryTokens: Tokens
}

public enum DuplicationAnalyzer {
  public static func run(_ lane: Lane) -> DuplicationAnalysis {
    let end = lane.snapshots.count
    var byHash: [UInt64: [Segment]] = [:]
    for segment in lane.segments where segment.characters > 0 {
      byHash[segment.contentHash, default: []].append(segment)
    }

    var groups: [DuplicateGroup] = []
    var wasted = 0
    var wastedGrade = Grade.measured
    for (hash, segments) in byHash where segments.count > 1 {
      let sorted = segments.sorted { $0.born < $1.born }
      // An interval sweep, not a scan of every request against every copy:
      // the events are the births and deaths, and between two events nothing
      // changes. The scan version went from 78 ms to 1.2 s for four times the
      // requests, which is the wrong shape for a 1M token window.
      var events: [(request: Int, delta: Int, tokens: Int)] = []
      events.reserveCapacity(sorted.count * 2)
      for segment in sorted {
        events.append((segment.born, 1, segment.tokens.value))
        events.append((min(segment.died ?? end, end), -1, segment.tokens.value))
      }
      events.sort { $0.request == $1.request ? $0.delta < $1.delta : $0.request < $1.request }

      var overlapCost = 0
      var firstOverlap: Int?
      var alive = 0
      var aliveTokens = 0
      var smallestAlive = 0
      var previous = events.first?.request ?? 0
      var index = 0
      while index < events.count {
        let request = events[index].request
        // Charge the span that just ended, at the state it was held in.
        if alive > 1, request > previous {
          if firstOverlap == nil { firstOverlap = previous }
          overlapCost += (aliveTokens - smallestAlive) * (request - previous)
        }
        while index < events.count, events[index].request == request {
          alive += events[index].delta
          aliveTokens += events[index].delta * events[index].tokens
          index += 1
        }
        // Copies of the same content can differ in size, so the one that is
        // not waste is the smallest of those alive.
        smallestAlive =
          sorted.filter { $0.isLive(at: request) }.map(\.tokens.value).min() ?? 0
        previous = request
      }
      guard let overlap = firstOverlap else { continue }
      wasted += overlapCost
      for segment in sorted { wastedGrade = max(wastedGrade, segment.tokens.grade) }
      groups.append(
        DuplicateGroup(
          contentHash: hash,
          segments: sorted.map(\.id),
          label: sorted[0].label,
          copyTokens: sorted.map(\.tokens),
          wastedCarryTokens: Tokens(
            overlapCost, sorted.map(\.tokens.grade).max() ?? .estimated),
          firstOverlap: overlap
        )
      )
    }
    groups.sort {
      $0.wastedCarryTokens.value == $1.wastedCarryTokens.value
        ? $0.contentHash < $1.contentHash
        : $0.wastedCarryTokens.value > $1.wastedCarryTokens.value
    }
    return DuplicationAnalysis(
      groups: groups, wastedCarryTokens: Tokens(wasted, wastedGrade))
  }
}
