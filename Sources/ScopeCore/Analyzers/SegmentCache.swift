/// Cache state per segment and per request: whether a segment's tokens were
/// read from the cache or written to it, and how often they have been
/// written.
///
/// The cache boundary is a prefix of the prompt, so the question is only
/// "where does `cache_read_input_tokens` end". Everything before it was read,
/// everything after it was written or sent uncached. That is why this has to
/// walk true prompt order and not band order.
///
/// It stays linear. A request normally writes exactly what entered at it, and
/// then only the new segments are marked. Only when more was written than
/// entered, which is a cache bust or a compaction, does it walk the live set.

public enum CacheStateKind: String, Sendable, Codable, CaseIterable {
  case read
  case written
  case uncached
}

public struct SegmentCacheState: Sendable, Codable, Hashable {
  public let segment: SegmentID
  /// How often this segment's tokens have been written to the cache. One is
  /// the floor: everything is written once when it enters.
  public let writes: Int
  public let firstWrite: Int
  public let lastWrite: Int
  public let grade: Grade
}

public struct SegmentCacheAnalysis: Sendable, Codable {
  public let perSegment: [SegmentCacheState]
  /// Tokens read from cache at each request. The boundary in prompt order
  /// between what the model paid for and what it did not.
  public let readBoundary: [Int]
  /// Requests where more was written than entered, so something older had to
  /// be written again, with the segments that were written again at each.
  /// Everywhere else what was written is what entered.
  public let rewritten: [Int: Set<SegmentID>]

  public var rewriteRequests: [Int] { rewritten.keys.sorted() }

  /// Whether a segment's tokens were written to the cache at a request rather
  /// than read out of it.
  public func isWritten(_ segment: SegmentID, born: Int, at request: Int) -> Bool {
    if let written = rewritten[request] { return written.contains(segment) }
    return born == request
  }

  public func writes(of segment: SegmentID) -> Int {
    perSegment.first { $0.segment == segment }?.writes ?? 0
  }

  /// What happened to one segment at one request. Needs the lane because the
  /// answer depends on where the segment sits in the prompt.
  public func state(of segment: SegmentID, at request: Int, in lane: Lane) -> CacheStateKind? {
    guard request >= 0, request < readBoundary.count else { return nil }
    var offset = 0
    for candidate in lane.promptOrderSegments(at: request) {
      let end = offset + candidate.tokens.value
      if candidate.id == segment {
        return offset < readBoundary[request] ? .read : .written
      }
      offset = end
    }
    return nil
  }
}

public enum SegmentCacheAnalyzer {
  /// A request that writes no more than a few tokens beyond what entered is
  /// just caching the new content. Anything past this had to write something
  /// older again.
  private static let rewriteTolerance = 64

  public static func run(_ lane: Lane) -> SegmentCacheAnalysis {
    let count = lane.snapshots.count
    var writes = [Int](repeating: 0, count: lane.segments.count)
    var firstWrite = [Int](repeating: -1, count: lane.segments.count)
    var lastWrite = [Int](repeating: -1, count: lane.segments.count)
    var boundary = [Int](repeating: 0, count: count)
    var rewrites: [Int: Set<SegmentID>] = [:]

    var slotOf: [SegmentID: Int] = [:]
    for (slot, segment) in lane.segments.enumerated() { slotOf[segment.id] = slot }
    var bornAt = [[Int]](repeating: [], count: max(1, count))
    for (slot, segment) in lane.segments.enumerated() where segment.born < count {
      bornAt[segment.born].append(slot)
    }

    func markWritten(_ slot: Int, at request: Int) {
      writes[slot] += 1
      if firstWrite[slot] < 0 { firstWrite[slot] = request }
      lastWrite[slot] = request
    }

    for request in 0..<count {
      let usage = lane.snapshots[request].usage
      boundary[request] = usage.cacheReadTokens
      let entered = bornAt[request].reduce(0) { $0 + lane.segments[$1].tokens.value }
      let beyond = usage.cacheCreationTokens - entered

      guard beyond > rewriteTolerance else {
        for slot in bornAt[request] { markWritten(slot, at: request) }
        continue
      }
      // Something older was written again. Find where the read prefix ends.
      var offset = 0
      var written: Set<SegmentID> = []
      for segment in lane.promptOrderSegments(at: request) {
        if offset >= usage.cacheReadTokens, let slot = slotOf[segment.id] {
          markWritten(slot, at: request)
          written.insert(segment.id)
        }
        offset += segment.tokens.value
      }
      rewrites[request] = written
    }

    let states = lane.segments.indices.map { slot in
      SegmentCacheState(
        segment: lane.segments[slot].id,
        writes: writes[slot],
        firstWrite: firstWrite[slot],
        lastWrite: lastWrite[slot],
        // The usage that decides this is measured; which side of the boundary
        // a segment falls on depends on its size, which is not.
        grade: lane.segments[slot].tokens.grade == .measured ? .measured : .derived
      )
    }
    return SegmentCacheAnalysis(
      perSegment: states, readBoundary: boundary, rewritten: rewrites)
  }
}
