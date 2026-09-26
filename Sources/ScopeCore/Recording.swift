/// The immutable, ordered result of observing one session. All analysis is a
/// pure function of a recording.

public struct LaneID: Hashable, Sendable, Codable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public static let main = LaneID("main")
}

/// One agent's recording. A session has a main lane plus one lane per
/// subagent.
public struct Lane: Sendable, Codable {
  public let id: LaneID
  /// The kind of subagent, when this is one.
  public let agentType: String?
  /// The `tool_use` id in the parent lane that spawned this one.
  public let parentToolUseID: String?
  /// How large the window was, and how sure we are of it.
  public let window: WindowEstimate
  public let segments: [Segment]
  public let snapshots: [Snapshot]
  public let compactions: [CompactionEvent]
  /// Everything that happened to this lane's context, with its provenance.
  public let events: [LaneEvent]
  /// The blocks that are prompts the person typed, in the order they entered.
  /// A task runs from one of them to the next.
  public let prompts: [SegmentID]
  /// Rates the estimator ended up using for this lane.
  public let calibration: EstimatorRates
  /// What the capture had to cope with while building this lane.
  public let stats: CaptureStats
  /// Where the split of the unobserved prefix came from.
  public let prefixSource: PrefixSplit.Source
  /// The harness's own account of what fills the context, when somebody ran
  /// `/context` in this lane. It is what `validate` holds the bands against.
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

  /// An older recording has neither, and reading one back is not a reason to
  /// fail.
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

  /// Where this lane's length zones sit at one request.
  ///
  /// Zones are per model and a lane can change model half way through, so the
  /// scale is resolved from the request being asked about rather than from the
  /// first one. The one place that decides this, so a ruler and a lookup can
  /// never disagree.
  public func zones(at request: Int) -> ZoneScale {
    guard !snapshots.isEmpty else { return .default }
    return ZoneScale.forModel(snapshots[max(0, min(request, snapshots.count - 1))].model)
  }

  /// Segments alive at a request, grouped by band. This is the order the time
  /// view stacks them in, not the order the model read them in.
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

  /// Segments alive at a request, in the order the model actually read them:
  /// the fixed prefix first, then the conversation in the order it happened.
  ///
  /// Anything about position has to use this. Grouping by band puts every
  /// file read next to every other file read no matter when it arrived, so a
  /// "middle third" measured on that order is whichever band happens to land
  /// there, not the middle of the prompt.
  public func promptOrderSegments(at request: Int) -> [Segment] {
    segments.filter { $0.isLive(at: request) }.sorted(by: Self.readsBefore)
  }

  /// Whether the model reads one segment before another. The key does not
  /// depend on the request, so one sort of a whole lane is its reading order
  /// at every request, and filtering that order is all a request costs.
  public static func readsBefore(_ left: Segment, _ right: Segment) -> Bool {
    let leftRank = promptRank(left)
    let rightRank = promptRank(right)
    if leftRank != rightRank { return leftRank < rightRank }
    if left.born != right.born { return left.born < right.born }
    return left.id < right.id
  }

  /// The prefix keeps its band order because that is the order it is built
  /// in. Everything after it is chronological.
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
