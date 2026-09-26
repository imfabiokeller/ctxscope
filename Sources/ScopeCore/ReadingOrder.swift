public struct ReadingOrder: Sendable {
  public struct Slice: Sendable, Hashable {
    public let segment: SegmentID
    public let band: Band
    public let start: Int
    public let tokens: Int
    public let grade: Grade

    public var kind: Kind? { BandRegistry.kind(of: band) }
    public var end: Int { start + tokens }
  }

  public struct Column: Sendable, Hashable {
    public let request: Int
    public let slices: [Slice]
    public let cacheBoundary: Int
    public let prefixEnd: Int

    public var end: Int { slices.last?.end ?? 0 }
  }

  private let segments: [Segment]
  private let order: [Int]
  private let cacheRead: [Int]

  public init(_ lane: Lane) {
    segments = lane.segments
    order = lane.segments.indices.sorted {
      Lane.readsBefore(lane.segments[$0], lane.segments[$1])
    }
    cacheRead = lane.snapshots.map(\.usage.cacheReadTokens)
  }

  public var requestCount: Int { cacheRead.count }

  public func column(at request: Int) -> Column {
    guard request >= 0, request < cacheRead.count else {
      return Column(request: request, slices: [], cacheBoundary: 0, prefixEnd: 0)
    }
    var slices: [Slice] = []
    var offset = 0
    var prefixEnd = 0
    for slot in order where segments[slot].isLive(at: request) {
      let segment = segments[slot]
      slices.append(
        Slice(
          segment: segment.id, band: segment.band, start: offset,
          tokens: segment.tokens.value, grade: segment.tokens.grade))
      offset += segment.tokens.value
      if segment.family == .prefix { prefixEnd = offset }
    }
    return Column(
      request: request, slices: slices, cacheBoundary: cacheRead[request], prefixEnd: prefixEnd)
  }
}
