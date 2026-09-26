public import ScopeCore

public struct LaneAnalysis: Sendable {
  public let session: String
  public let lane: Lane
  public let references: ReferenceReport
  public let findings: [SegmentID: ReferenceFinding]
  public let tally: Tally
  public let cache: CacheAnalysis
  public let carry: CarryCostAnalysis
  public let costs: CostAnalysis
  public let segmentCache: SegmentCacheAnalysis
  public let prompts: PromptAnalysis
  public let readingOrder: ReadingOrder

  public init(session: String, lane: Lane, references: ReferenceReport) {
    self.session = session
    self.lane = lane
    self.references = references
    findings = references.bySegment()
    tally = TallyAnalyzer.run(lane)
    let cache = CacheAnalyzer.run(lane)
    self.cache = cache
    carry = CarryCostAnalyzer.run(lane, references: references)
    let costs = CostAnalyzer.run(lane)
    self.costs = costs
    segmentCache = SegmentCacheAnalyzer.run(lane)
    prompts = PromptAnalyzer.run(lane, costs: costs, cache: cache)
    readingOrder = ReadingOrder(lane)
  }

  public var requestCount: Int { lane.snapshots.count }
  public var lastRequest: Int { max(0, lane.snapshots.count - 1) }

  public func figures(at request: Int) -> PlayheadFigures {
    PlayheadFigures(analysis: self, request: clamped(request))
  }

  public func finding(of segment: SegmentID) -> ReferenceFinding? { findings[segment] }

  public func topUnreferenced(at request: Int, count: Int) -> [SegmentCost] {
    CarryCostAnalyzer.top(lane, references: references, upTo: request, count: count)
  }

  public func tally(at request: Int) -> RequestTally? {
    let index = clamped(request)
    guard index < tally.perRequest.count else { return nil }
    return tally.perRequest[index]
  }

  public func segment(_ id: SegmentID) -> Segment? {
    let slot = id.rawValue
    guard slot >= 0, slot < lane.segments.count, lane.segments[slot].id == id else {
      return lane.segments.first { $0.id == id }
    }
    return lane.segments[slot]
  }

  private func clamped(_ request: Int) -> Int {
    max(0, min(request, max(0, lane.snapshots.count - 1)))
  }
}
