public enum BlockUse: String, Sendable, Codable, CaseIterable {
  case used
  case unused
  case notTracked
}

public struct UnusedSummary: Sendable, Codable, Hashable {
  public let request: Int
  public let tokens: Tokens
  public let blocks: Int
  public let share: Double
  public let dollars: Double
}

public enum UseAnalyzer {
  public static func use(
    of segment: Segment, finding: ReferenceFinding?, at request: Int
  ) -> BlockUse {
    guard BandRegistry.countsTowardsReuseRatio(segment.band) else { return .notTracked }
    guard let finding else { return segment.isAssessable ? .unused : .notTracked }
    guard let share = finding.share(at: request) else { return .notTracked }
    return share > 0 ? .used : .unused
  }

  public static func called(
    _ segment: Segment, finding: ReferenceFinding?, at request: Int
  ) -> Bool? {
    guard BandRegistry.kind(of: segment.band) == .tools, let finding, finding.isAssessable,
      let share = finding.share(at: request)
    else { return nil }
    return share > 0
  }

  public static func unused(
    _ lane: Lane,
    findings: [SegmentID: ReferenceFinding],
    costs: BlockCostAnalysis,
    at request: Int
  ) -> UnusedSummary {
    guard !lane.snapshots.isEmpty else {
      return UnusedSummary(
        request: request, tokens: Tokens(0, .estimated), blocks: 0, share: 0, dollars: 0)
    }
    let at = max(0, min(request, lane.snapshots.count - 1))
    var tokens = 0
    var blocks = 0
    var dollars = 0.0
    for segment in lane.segments where segment.isLive(at: at) {
      guard use(of: segment, finding: findings[segment.id], at: at) == .unused else { continue }
      tokens += segment.tokens.value
      blocks += 1
      dollars += costs.cost(of: segment.id)?.dollars ?? 0
    }
    let total = lane.snapshots[at].usage.promptTotal
    return UnusedSummary(
      request: at,
      tokens: Tokens(tokens, .estimated),
      blocks: blocks,
      share: total > 0 ? Double(tokens) / Double(total) : 0,
      dollars: dollars
    )
  }
}
