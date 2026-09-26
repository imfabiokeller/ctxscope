internal import Foundation
public import ScopeCore

public struct SessionCapture: Sendable {
  public let session: SessionRef
  private let includeSubagents: Bool
  private let window: WindowEstimate?
  public var windowHints: ModelWindowHints {
    didSet {
      main.builder.windowHints = windowHints
      for id in subagents.keys { subagents[id]?.builder.windowHints = windowHints }
    }
  }
  private var main: Tracked
  private var subagents: [LaneID: Tracked] = [:]
  private var knownSubagents: Set<String> = []

  private struct Tracked: Sendable {
    var url: URL
    var position: JSONLReader.Position
    var builder: LaneBuilder
  }

  public struct Refresh: Sendable {
    public var newLines = 0
    public var skippedLines = 0
    public var newRequests = 0
    public var filesRead = 0
    public var rebuiltLanes = 0

    public init() {}
  }

  public init(
    session: SessionRef,
    includeSubagents: Bool,
    window: WindowEstimate?,
    windowHints: ModelWindowHints = ModelWindowHints()
  ) {
    self.session = session
    self.includeSubagents = includeSubagents
    self.window = window
    self.windowHints = windowHints
    main = Tracked(
      url: session.url,
      position: .start,
      builder: LaneBuilder(
        id: .main, agentType: nil, parentToolUseID: nil, window: window, url: session.url,
        windowHints: windowHints)
    )
  }

  public func content(of segment: SegmentID, lane: LaneID = .main) -> SegmentContent? {
    if lane == .main { return main.builder.content(of: segment) }
    return subagents[lane]?.builder.content(of: segment)
  }

  public func details(of segments: [SegmentID], lane: LaneID = .main) -> [SegmentID: BlockDetail] {
    if lane == .main { return main.builder.details(of: segments) }
    return subagents[lane]?.builder.details(of: segments) ?? [:]
  }

  @discardableResult
  public mutating func refresh(shouldStop: () -> Bool = { false }) throws -> Refresh {
    var refresh = Refresh()
    try Self.advance(&main, refresh: &refresh, shouldStop: shouldStop)
    guard includeSubagents else { return refresh }
    for reference in try ClaudeCodeAdapter.subagents(of: session) {
      if subagents[reference.lane] == nil {
        guard knownSubagents.insert(reference.url.path).inserted else { continue }
        subagents[reference.lane] = Tracked(
          url: reference.url,
          position: .start,
          builder: LaneBuilder(
            id: reference.lane,
            agentType: reference.agentType,
            parentToolUseID: reference.toolUseID,
            window: window,
            url: reference.url,
            windowHints: windowHints
          )
        )
      }
      guard var tracked = subagents[reference.lane] else { continue }
      try Self.advance(&tracked, refresh: &refresh, shouldStop: shouldStop)
      subagents[reference.lane] = tracked
      if shouldStop() { return refresh }
    }
    return refresh
  }

  private static let batchSize = 512

  // Prefix evidence found after the first request was stepped rebuilds the lane
  // once from the start, so every read order gives the same lane.
  private static func advance(
    _ tracked: inout Tracked, refresh: inout Refresh, shouldStop: () -> Bool
  ) throws {
    try read(&tracked, refresh: &refresh, shouldStop: shouldStop)
    guard tracked.builder.needsRestart else { return }
    tracked.builder = tracked.builder.restarted()
    tracked.position = .start
    refresh.rebuiltLanes += 1
    var again = Refresh()
    try read(&tracked, refresh: &again, shouldStop: shouldStop)
    refresh.filesRead += again.filesRead
    refresh.skippedLines = again.skippedLines
    refresh.newRequests = tracked.builder.snapshotOutput().lane.snapshots.count
  }

  private static func read(
    _ tracked: inout Tracked, refresh: inout Refresh, shouldStop: () -> Bool
  ) throws {
    let before = tracked.builder.snapshotOutput().lane.snapshots.count
    var batch: [TranscriptEntry] = []
    var skipped = 0
    var lines = 0

    func flush(_ builder: inout LaneBuilder) {
      guard !batch.isEmpty || skipped > 0 else { return }
      builder.append(batch, skippedLines: skipped)
      batch.removeAll(keepingCapacity: true)
      skipped = 0
    }

    // Resume after the last flushed batch; the rest is read again next time.
    var stopAfter: UInt64?
    let end = try JSONLReader(url: tracked.url).stream(from: tracked.position) { data, range in
      guard stopAfter == nil else { return }
      guard let value = try? JSONValue(parsing: data), value.object != nil else {
        skipped += 1
        return
      }
      lines += 1
      batch.append(TranscriptEntry(value, range: range))
      if batch.count >= Self.batchSize {
        flush(&tracked.builder)
        if shouldStop() { stopAfter = range.offset + UInt64(range.length) + 1 }
      }
    }
    guard lines > 0 || skipped > 0 else { return }
    if stopAfter == nil { flush(&tracked.builder) }
    tracked.builder.settle()

    refresh.filesRead += 1
    refresh.newLines += lines
    refresh.skippedLines += skipped
    refresh.newRequests += tracked.builder.snapshotOutput().lane.snapshots.count - before
    tracked.position = stopAfter.map(JSONLReader.Position.init) ?? end
  }

  public func current() -> CapturedSession {
    var outputs = [main.builder.snapshotOutput()]
    for id in subagents.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
      guard let tracked = subagents[id] else { continue }
      outputs.append(tracked.builder.snapshotOutput())
    }
    return assemble(outputs)
  }

  public mutating func finish() -> CapturedSession {
    var outputs = [main.builder.finish()]
    for id in subagents.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
      guard var tracked = subagents[id] else { continue }
      outputs.append(tracked.builder.finish())
      subagents[id] = tracked
    }
    return assemble(outputs)
  }

  private func assemble(_ outputs: [LaneBuilder.Output]) -> CapturedSession {
    var lanes: [Lane] = []
    var inputs: [LaneID: JudgeInput] = [:]
    var fits: [LaneID: EstimatorCalibration] = [:]
    for output in outputs {
      guard output.lane.id == .main || !output.lane.snapshots.isEmpty else { continue }
      lanes.append(output.lane)
      inputs[output.lane.id] = output.judgeInput
      fits[output.lane.id] = output.calibration
    }
    return CapturedSession(
      recording: Recording(
        sessionID: session.id,
        project: session.project,
        title: session.title,
        lanes: lanes
      ),
      judgeInputs: inputs,
      calibrations: fits
    )
  }
}
