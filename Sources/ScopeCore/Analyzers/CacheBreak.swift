public struct PrefixChange: Sendable, Codable, Hashable {
  public let kind: Kind
  public let first: SegmentID
  public let firstLabel: String
  public let added: [SegmentID]
  public let addedTokens: Tokens
  public let removed: [SegmentID]
  public let removedTokens: Tokens
  public let servers: [String]
}

extension CacheAnalyzer {
  static func prefixMoves(_ lane: Lane) -> [Int: [Segment]] {
    var moves: [Int: [Segment]] = [:]
    for segment in lane.segments where segment.family == .prefix {
      if segment.born > 0 { moves[segment.born, default: []].append(segment) }
      if let died = segment.died { moves[died, default: []].append(segment) }
    }
    return moves
  }

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

  /// Counts a block as read when it starts before the boundary, as `SegmentCacheAnalyzer` does.
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
