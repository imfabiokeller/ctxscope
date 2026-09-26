/// Every block of a lane in the order the model reads it, with where it sits
/// in tokens at any request. One slice per block, never runs of a kind: the
/// context strip and every column of the timeline draw from this.
///
/// The lane is sorted once, with `Lane.readsBefore`, when this is made. A
/// column is then that order filtered to what is live, so a request costs one
/// pass over the lane's blocks and a timeline of a few hundred columns over a
/// few thousand blocks is a few hundred passes, done once per change and not
/// per frame.
public struct ReadingOrder: Sendable {
  /// One block at one request.
  public struct Slice: Sendable, Hashable {
    public let segment: SegmentID
    public let band: Band
    /// Tokens before this block in the context of the request.
    public let start: Int
    public let tokens: Int
    public let grade: Grade

    /// Nil for unattributed tokens, which are drawn as an untyped remainder.
    public var kind: Kind? { BandRegistry.kind(of: band) }
    public var end: Int { start + tokens }
  }

  /// One request's context, in reading order, in one coordinate space: tokens
  /// from the start of the prompt.
  public struct Column: Sendable, Hashable {
    public let request: Int
    public let slices: [Slice]
    /// Where what was read from the cache ends: "cached up to here". The API's
    /// own count, so exact.
    public let cacheBoundary: Int
    /// Where the part sent with every request ends: system, tools and memory,
    /// which reading order puts first.
    public let prefixEnd: Int

    /// Where the last block ends. In a lane whose blocks account for every
    /// token this is the measured total of the request.
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

  /// The context of one request. Empty for a request the lane does not have.
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
