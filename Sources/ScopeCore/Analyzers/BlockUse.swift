/// Whether a block was used, as of a request, and what the unused part of the
/// context carries.
///
/// "Used" means some later text reused the block word for word by then. It
/// is read from the judge's findings with `ReferenceFinding.share(at:)`, which
/// is made only of what had happened by that request, so moving the playhead
/// back never shows a use from the future.

public enum BlockUse: String, Sendable, Codable, CaseIterable {
  case used
  case unused
  /// Reuse cannot be observed for this block: a rule, a tool definition, an
  /// image, or anything the judge was given no words of.
  case notTracked
}

/// The unused part of the context at one request.
public struct UnusedSummary: Sendable, Codable, Hashable {
  public let request: Int
  /// Tokens of the live blocks judged unused. Estimated: the judge is, and so
  /// are most sizes.
  public let tokens: Tokens
  public let blocks: Int
  /// `tokens` as a share of the measured context of the request.
  public let share: Double
  /// Their attributed cost so far.
  public let dollars: Double
}

public enum UseAnalyzer {
  /// Used, unused, or not tracked, as of a request.
  ///
  /// A tool definition is not tracked here. Whether its tool was called is a
  /// different fact with its own column, `called`, and the reuse ratio keeps
  /// it out for the same reason (`BandRegistry.countsTowardsReuseRatio`).
  public static func use(
    of segment: Segment, finding: ReferenceFinding?, at request: Int
  ) -> BlockUse {
    guard BandRegistry.countsTowardsReuseRatio(segment.band) else { return .notTracked }
    guard let finding else { return segment.isAssessable ? .unused : .notTracked }
    guard let share = finding.share(at: request) else { return .notTracked }
    return share > 0 ? .used : .unused
  }

  /// Whether a tool definition's tool had been called by a request. Nil for
  /// anything that is not a tool definition, and for a tool block the
  /// transcript never named, which is a share of the prefix rather than one
  /// tool.
  public static func called(
    _ segment: Segment, finding: ReferenceFinding?, at request: Int
  ) -> Bool? {
    guard BandRegistry.kind(of: segment.band) == .tools, let finding, finding.isAssessable,
      let share = finding.share(at: request)
    else { return nil }
    return share > 0
  }

  /// The live blocks judged unused at a request: how many tokens, what share
  /// of the context, and what they have cost so far.
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
