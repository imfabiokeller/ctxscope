public struct CacheState: Sendable, Codable, Hashable {
  public let request: Int
  public let readTokens: Tokens
  public let writtenTokens: Tokens
  public let uncachedTokens: Tokens
  public let hit: Double
}

public enum CacheBustCause: String, Sendable, Codable, CaseIterable {
  case compaction
  case modelSwitch
  case rewind
  case systemChanged
  case toolsChanged
  case memoryChanged
  case idle
  case unknown
}

public struct CacheBust: Sendable, Codable, Hashable {
  public let request: Int
  public let expectedReadTokens: Int
  public let actualReadTokens: Int
  public let rewrittenTokens: Tokens
  public let cause: CacheBustCause
  public let parentRequest: Int
  public let gapSeconds: Double
  public let change: PrefixChange?
  public let readThrough: Kind?
}

public struct CacheAnalysis: Sendable, Codable {
  public let perRequest: [CacheState]
  public let busts: [CacheBust]
  public let totalWritten: Tokens
  public let totalRead: Tokens
}

public enum CacheAnalyzer {
  /// The API's two cache lifetimes. A pause can only have expired the cache if it was
  /// longer than the lifetime the parent request wrote at.
  public static let idleSeconds: Double = 300
  public static let idleSecondsOneHour: Double = 3600

  /// The lifetime in force before a request: one hour when the nearest earlier request
  /// that wrote to the cache wrote one-hour entries, else five minutes.
  public static func lifetime(before index: Int, in lane: Lane) -> Double {
    var cursor = index
    while cursor >= 0 {
      let usage = lane.snapshots[cursor].usage
      if usage.cacheCreationTokens > 0 {
        return usage.ephemeral1hTokens > usage.ephemeral5mTokens ? idleSecondsOneHour : idleSeconds
      }
      cursor -= 1
    }
    return idleSeconds
  }

  public static func run(_ lane: Lane) -> CacheAnalysis {
    var states: [CacheState] = []
    states.reserveCapacity(lane.snapshots.count)
    var busts: [CacheBust] = []
    var totalWritten = 0
    var totalRead = 0
    var compactionAt = Set(lane.compactions.map(\.atRequest))
    for event in lane.events where event.kind == .compaction { compactionAt.insert(event.request) }
    let switchedAt = Set(lane.events.filter { $0.kind == .modelSwitch }.map(\.request))
    let prefixMoves = prefixMoves(lane)

    for snapshot in lane.snapshots {
      let usage = snapshot.usage
      states.append(
        CacheState(
          request: snapshot.index,
          readTokens: Tokens(usage.cacheReadTokens, .measured),
          writtenTokens: Tokens(usage.cacheCreationTokens, .measured),
          uncachedTokens: Tokens(usage.inputTokens, .measured),
          hit: usage.cacheHit
        )
      )
      totalWritten += usage.cacheCreationTokens
      totalRead += usage.cacheReadTokens

      let parentIndex = snapshot.parentRequest ?? (snapshot.index - 1)
      guard parentIndex >= 0, parentIndex < lane.snapshots.count else { continue }
      let parent = lane.snapshots[parentIndex]
      guard usage.cacheReadTokens < parent.usage.cachedAfter else { continue }
      let change = prefixChange(prefixMoves[snapshot.index] ?? [], at: snapshot.index)
      busts.append(
        CacheBust(
          request: snapshot.index,
          expectedReadTokens: parent.usage.cachedAfter,
          actualReadTokens: usage.cacheReadTokens,
          rewrittenTokens: Tokens(parent.usage.cachedAfter - usage.cacheReadTokens, .derived),
          cause: cause(
            snapshot: snapshot,
            parent: parent,
            parentIndex: parentIndex,
            compactionAt: compactionAt,
            switchedAt: switchedAt,
            change: change,
            lifetime: lifetime(before: parentIndex, in: lane)
          ),
          parentRequest: parentIndex,
          gapSeconds: snapshot.timestamp - parent.timestamp,
          change: change,
          readThrough: readThrough(lane, at: snapshot.index, read: usage.cacheReadTokens)
        )
      )
    }
    return CacheAnalysis(
      perRequest: states,
      busts: busts,
      totalWritten: Tokens(totalWritten, .measured),
      totalRead: Tokens(totalRead, .measured)
    )
  }

  private static func cause(
    snapshot: Snapshot,
    parent: Snapshot,
    parentIndex: Int,
    compactionAt: Set<Int>,
    switchedAt: Set<Int>,
    change: PrefixChange?,
    lifetime: Double
  ) -> CacheBustCause {
    if compactionAt.contains(snapshot.index) { return .compaction }
    if switchedAt.contains(snapshot.index) || snapshot.model != parent.model {
      return .modelSwitch
    }
    if parentIndex != snapshot.index - 1 { return .rewind }
    // A changed prefix block is observed; a pause only might have expired the
    // cache, so it is checked after.
    switch change?.kind {
    case .system: return .systemChanged
    case .tools: return .toolsChanged
    case .memory: return .memoryChanged
    default: break
    }
    let gap = snapshot.timestamp - parent.timestamp
    if gap >= lifetime { return .idle }
    return .unknown
  }
}
