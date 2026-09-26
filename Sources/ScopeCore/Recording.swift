public struct LaneID: Hashable, Sendable, Codable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public static let main = LaneID("main")
}

public struct Lane: Sendable, Codable {
  public let id: LaneID
  public let agentType: String?
  public let parentToolUseID: String?
  public let window: WindowEstimate
  public let segments: [Segment]
  public let snapshots: [Snapshot]
  public let compactions: [CompactionEvent]
  public let events: [LaneEvent]
  public let prompts: [SegmentID]
  public let calibration: EstimatorRates
  public let stats: CaptureStats
  public let prefixSource: PrefixSplit.Source
  public let contextReport: ContextReport?

  public init(
    id: LaneID,
    agentType: String? = nil,
    parentToolUseID: String? = nil,
    window: WindowEstimate,
    segments: [Segment],
    snapshots: [Snapshot],
    compactions: [CompactionEvent] = [],
    events: [LaneEvent] = [],
    prompts: [SegmentID] = [],
    calibration: EstimatorRates = .prior,
    stats: CaptureStats = CaptureStats(),
    prefixSource: PrefixSplit.Source = .prior,
    contextReport: ContextReport? = nil
  ) {
    self.id = id
    self.agentType = agentType
    self.parentToolUseID = parentToolUseID
    self.window = window
    self.segments = segments
    self.snapshots = snapshots
    self.compactions = compactions
    self.events = events
    self.prompts = prompts
    self.calibration = calibration
    self.stats = stats
    self.prefixSource = prefixSource
    self.contextReport = contextReport
  }

  /// Older recordings lack the later fields, and reading one back must not fail.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(LaneID.self, forKey: .id)
    agentType = try values.decodeIfPresent(String.self, forKey: .agentType)
    parentToolUseID = try values.decodeIfPresent(String.self, forKey: .parentToolUseID)
    window = try values.decode(WindowEstimate.self, forKey: .window)
    segments = try values.decode([Segment].self, forKey: .segments)
    snapshots = try values.decode([Snapshot].self, forKey: .snapshots)
    compactions = try values.decodeIfPresent([CompactionEvent].self, forKey: .compactions) ?? []
    events = try values.decodeIfPresent([LaneEvent].self, forKey: .events) ?? []
    prompts = try values.decodeIfPresent([SegmentID].self, forKey: .prompts) ?? []
    calibration = try values.decodeIfPresent(EstimatorRates.self, forKey: .calibration) ?? .prior
    stats = try values.decodeIfPresent(CaptureStats.self, forKey: .stats) ?? CaptureStats()
    prefixSource =
      try values.decodeIfPresent(PrefixSplit.Source.self, forKey: .prefixSource) ?? .prior
    contextReport = try values.decodeIfPresent(ContextReport.self, forKey: .contextReport)
  }

  public var requestCount: Int { snapshots.count }

  public func zones(at request: Int) -> ZoneScale {
    guard !snapshots.isEmpty else { return .default }
    return ZoneScale.forModel(snapshots[max(0, min(request, snapshots.count - 1))].model)
  }

  public func liveSegments(at request: Int) -> [Segment] {
    segments.filter { $0.isLive(at: request) }
      .sorted {
        let left = BandRegistry.position(of: $0.band)
        let right = BandRegistry.position(of: $1.band)
        if left != right { return left < right }
        if $0.born != $1.born { return $0.born < $1.born }
        return $0.id < $1.id
      }
  }

  /// Anything about position must use this, not `liveSegments`, which groups by band.
  public func promptOrderSegments(at request: Int) -> [Segment] {
    segments.filter { $0.isLive(at: request) }.sorted(by: Self.readsBefore)
  }

  /// The key does not depend on the request, so one sort serves every request.
  public static func readsBefore(_ left: Segment, _ right: Segment) -> Bool {
    let leftRank = promptRank(left)
    let rightRank = promptRank(right)
    if leftRank != rightRank { return leftRank < rightRank }
    if left.born != right.born { return left.born < right.born }
    return left.id < right.id
  }

  private static func promptRank(_ segment: Segment) -> Int {
    BandRegistry.family(of: segment.band) == .prefix
      ? BandRegistry.position(of: segment.band)
      : BandRegistry.ordered.count
  }
}

public struct Recording: Sendable, Codable {
  public let sessionID: String
  public let project: String
  public let title: String?
  public let lanes: [Lane]

  public init(sessionID: String, project: String, title: String?, lanes: [Lane]) {
    self.sessionID = sessionID
    self.project = project
    self.title = title
    self.lanes = lanes
  }

  public var mainLane: Lane? {
    lanes.first { $0.id == .main } ?? lanes.first
  }

  public func lane(_ id: LaneID) -> Lane? {
    lanes.first { $0.id == id }
  }
}
