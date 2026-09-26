internal import Foundation
public import ScopeCore

/// One session, kept open.
///
/// `refresh()` reads only the lines that have arrived since the last call and
/// feeds them to the lane builders, which keep every request they already
/// processed. Following a live session therefore costs its new lines, not the
/// 117 MB behind them.
public struct SessionCapture: Sendable {
  public let session: SessionRef
  private let includeSubagents: Bool
  private let window: WindowEstimate?
  /// What other sessions of the same model were seen to hold. A session that
  /// has not filled its own window yet would otherwise report the next size
  /// down and then jump.
  public var windowHints: ModelWindowHints {
    didSet {
      main.builder.windowHints = windowHints
      for id in subagents.keys { subagents[id]?.builder.windowHints = windowHints }
    }
  }
  private var main: Tracked
  private var subagents: [LaneID: Tracked] = [:]
  private var knownSubagents: Set<String> = []

  /// One file and the lane being built from it.
  private struct Tracked: Sendable {
    var url: URL
    var position: JSONLReader.Position
    var builder: LaneBuilder
  }

  /// What one refresh had to do. The numbers a test asserts on to show the
  /// work is proportional to the new lines.
  public struct Refresh: Sendable {
    public var newLines = 0
    public var skippedLines = 0
    public var newRequests = 0
    public var filesRead = 0
    /// Lanes that were built again because the transcript said something new
    /// about the prefix after the prefix had been derived. It happens at most
    /// once per lane: once the evidence is in hand there is nothing left to
    /// learn, so a long live lane never rebuilds on a later refresh.
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

  /// The text one segment was built from. Read back out of the transcript, so
  /// nothing holds it between requests.
  public func content(of segment: SegmentID, lane: LaneID = .main) -> SegmentContent? {
    if lane == .main { return main.builder.content(of: segment) }
    return subagents[lane]?.builder.content(of: segment)
  }

  /// What each of these segments of a lane is about, read back out of the
  /// transcript, for the window to show and nothing to keep.
  public func details(of segments: [SegmentID], lane: LaneID = .main) -> [SegmentID: BlockDetail] {
    if lane == .main { return main.builder.details(of: segments) }
    return subagents[lane]?.builder.details(of: segments) ?? [:]
  }

  /// Reads whatever has arrived. `shouldStop` is asked between batches, so a
  /// read of a large session can be given up on when nobody wants it any more.
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

  /// Entries handed to a builder at a time. Reading a 117 MB file into one
  /// array first puts the whole file in memory however little of it is needed,
  /// and a first read is exactly when that happens.
  private static let batchSize = 512

  /// Reads whatever has arrived, and builds the lane again when the file
  /// turned out to say something new about the prefix.
  ///
  /// The records that describe the prefix sit wherever the harness wrote them:
  /// the system prompt before the first response, the tool list before the
  /// second, a `/context` run wherever somebody typed it. The prefix is
  /// derived at the first request, so evidence that arrives after that request
  /// was stepped describes a lane that has already been built, and the lane is
  /// built again rather than patched. That is what makes the result the same
  /// whether a file is read whole, in batches, or a line at a time from any
  /// position.
  ///
  /// The rebuild is bounded: the evidence found so far is handed to the new
  /// builder, so the second pass cannot discover anything the first did not,
  /// and a lane is therefore built again at most once per piece of evidence.
  /// A file read whole, or in the batches this reads in, almost never needs
  /// one: both snapshots sit in the first batch. It costs one more pass over
  /// the file, which is why there is no pass before the first one.
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

    // Where to resume from when a read is given up on. Everything up to the
    // last flushed batch is in the builder; the rest is read again next time.
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

  /// The recording as it stands, with the request in flight left open.
  public func current() -> CapturedSession {
    var outputs = [main.builder.snapshotOutput()]
    for id in subagents.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
      guard let tracked = subagents[id] else { continue }
      outputs.append(tracked.builder.snapshotOutput())
    }
    return assemble(outputs)
  }

  /// The recording with every request closed, which is what a finished file
  /// should be read as.
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
