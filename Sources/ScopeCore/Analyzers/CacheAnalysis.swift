/// Cache state and cache busts, all of it measured.

public struct CacheState: Sendable, Codable, Hashable {
  public let request: Int
  public let readTokens: Tokens
  public let writtenTokens: Tokens
  public let uncachedTokens: Tokens
  /// cache read / (cache read + cache write + uncached input).
  public let hit: Double
}

/// Why the cache read dropped. A bust with no cause attached is a bust nobody
/// can act on, so every one of them gets the best answer available.
public enum CacheBustCause: String, Sendable, Codable, CaseIterable {
  /// The harness compacted, so everything behind the prefix changed.
  case compaction
  /// The model changed, and with it the prefix and the cache.
  case modelSwitch
  /// The request continued from something other than the one before it: a
  /// rewind, or an edited prompt.
  case rewind
  /// A block of the system prompt entered or left at this request.
  case systemChanged
  /// A tool definition entered or left: a server connected, or went away.
  case toolsChanged
  /// A memory file entered or left: a CLAUDE.md was edited, say.
  case memoryChanged
  /// A long enough pause that the cache entry expired.
  case idle
  case unknown
}

/// A request whose cache read dropped below what its parent had cached. The
/// difference is what had to be written again.
public struct CacheBust: Sendable, Codable, Hashable {
  public let request: Int
  public let expectedReadTokens: Int
  public let actualReadTokens: Int
  public let rewrittenTokens: Tokens
  public let cause: CacheBustCause
  /// The request the cache was compared against: the one this continued from.
  public let parentRequest: Int
  /// Seconds between the parent request and this one, which is what an
  /// expired cache is read from.
  public let gapSeconds: Double
  /// What entered or left the part sent with every request, when that is the
  /// cause.
  public let change: PrefixChange?
  /// The kind of the last block that was still read from the cache.
  /// Everything after it was written again: after the tools, it was
  /// everything after the system prompt and the tools. Nil when nothing was
  /// read, which means the whole context was.
  public let readThrough: Kind?
}

public struct CacheAnalysis: Sendable, Codable {
  public let perRequest: [CacheState]
  public let busts: [CacheBust]
  public let totalWritten: Tokens
  public let totalRead: Tokens
}

public enum CacheAnalyzer {
  /// The 5 minute cache entry, with room to spare. A gap longer than this is
  /// enough on its own to explain a cold cache.
  public static let idleSeconds: Double = 300

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

      // The comparison is against the request this one continued from, which
      // after a rewind is not the line before it in the file.
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
            change: change
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
    change: PrefixChange?
  ) -> CacheBustCause {
    if compactionAt.contains(snapshot.index) { return .compaction }
    if switchedAt.contains(snapshot.index) || snapshot.model != parent.model {
      return .modelSwitch
    }
    if parentIndex != snapshot.index - 1 { return .rewind }
    // A block of the prefix that changed is something the transcript shows.
    // A pause is only a reason the cache may have expired, so it comes after.
    switch change?.kind {
    case .system: return .systemChanged
    case .tools: return .toolsChanged
    case .memory: return .memoryChanged
    default: break
    }
    let gap = snapshot.timestamp - parent.timestamp
    if gap >= idleSeconds { return .idle }
    return .unknown
  }
}
