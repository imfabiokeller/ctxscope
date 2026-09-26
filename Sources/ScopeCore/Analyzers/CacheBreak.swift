/// The facts a cache break is explained with: which block of the part sent
/// with every request changed, and which part of the context was written
/// again. Facts only; the sentences are the window's.

/// What entered or left the prefix at one request.
public struct PrefixChange: Sendable, Codable, Hashable {
  /// The kind of the first changed block in reading order, which is the one
  /// that broke the cache: everything after it could no longer be read.
  public let kind: Kind
  public let first: SegmentID
  public let firstLabel: String
  /// Blocks of that kind that entered at the request, in reading order.
  public let added: [SegmentID]
  public let addedTokens: Tokens
  /// Blocks of that kind that left at the request.
  public let removed: [SegmentID]
  public let removedTokens: Tokens
  /// The MCP servers the changed tool definitions belong to, in the order
  /// they appear. Empty for any other kind, and for tool blocks nothing named.
  public let servers: [String]
}

extension CacheAnalyzer {
  /// Prefix blocks by the request they entered or left at, later than the
  /// first request. One pass over the lane, so a break is looked up rather
  /// than searched for.
  static func prefixMoves(_ lane: Lane) -> [Int: [Segment]] {
    var moves: [Int: [Segment]] = [:]
    for segment in lane.segments where segment.family == .prefix {
      if segment.born > 0 { moves[segment.born, default: []].append(segment) }
      if let died = segment.died { moves[died, default: []].append(segment) }
    }
    return moves
  }

  /// The change a set of prefix blocks that moved at one request amounts to.
  static func prefixChange(_ moved: [Segment], at request: Int) -> PrefixChange? {
    guard let first = moved.min(by: Lane.readsBefore),
      let kind = BandRegistry.kind(of: first.band)
    else { return nil }
    let same = moved.filter { BandRegistry.kind(of: $0.band) == kind }
      .sorted(by: Lane.readsBefore)
    let added = same.filter { $0.born == request }
    let removed = same.filter { $0.died == request }
    var servers: [String] = []
    for segment in same {
      guard case .mcp(let server?) = ToolGroupAnalyzer.server(of: segment),
        !servers.contains(server)
      else { continue }
      servers.append(server)
    }
    return PrefixChange(
      kind: kind,
      first: first.id,
      firstLabel: first.label,
      added: added.map(\.id),
      addedTokens: added.reduce(Tokens(0, .measured)) { $0 + $1.tokens },
      removed: removed.map(\.id),
      removedTokens: removed.reduce(Tokens(0, .measured)) { $0 + $1.tokens },
      servers: servers
    )
  }

  /// The kind of the last block that was read from the cache at a request, in
  /// reading order. Nil when nothing was read.
  ///
  /// A block counts as read when it starts before the boundary, the rule
  /// `SegmentCacheAnalyzer` writes blocks again by, so a block the estimator
  /// sized a little large is not reported as written again here and as read
  /// in the cost.
  static func readThrough(_ lane: Lane, at request: Int, read: Int) -> Kind? {
    var offset = 0
    var last: Kind?
    for segment in lane.promptOrderSegments(at: request) {
      guard offset < read else { break }
      if let kind = BandRegistry.kind(of: segment.band) { last = kind }
      offset += segment.tokens.value
    }
    return last
  }
}
