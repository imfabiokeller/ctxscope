public enum CacheStateKind: String, Sendable, Codable, CaseIterable {
  case read
  case written
  case uncached
}

public struct SegmentCacheState: Sendable, Codable, Hashable {
  public let segment: SegmentID
  public let writes: Int
  public let firstWrite: Int
  public let lastWrite: Int
  public let grade: Grade
}

public struct SegmentCacheAnalysis: Sendable, Codable {
  public let perSegment: [SegmentCacheState]
  public let readBoundary: [Int]
  public let rewritten: [Int: Set<SegmentID>]

  public var rewriteRequests: [Int] { rewritten.keys.sorted() }

  public func isWritten(_ segment: SegmentID, born: Int, at request: Int) -> Bool {
    if let written = rewritten[request] { return written.contains(segment) }
    return born == request
  }

  public func writes(of segment: SegmentID) -> Int {
    perSegment.first { $0.segment == segment }?.writes ?? 0
  }

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
  /// Writing up to this many tokens beyond what entered is just caching the new content.
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
        grade: lane.segments[slot].tokens.grade == .measured ? .measured : .derived
      )
    }
    return SegmentCacheAnalysis(
      perSegment: states, readBoundary: boundary, rewritten: rewrites)
  }
}
