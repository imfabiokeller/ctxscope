internal import Foundation
public import ScopeCapture
public import ScopeCore

/// Holds one open session off the main actor and answers in values.
///
/// Opening 08f59db8 takes about five seconds and analysing a lane takes tens
/// of milliseconds. None of that may happen on the main thread, so the session
/// itself lives here and the window only ever receives `Sendable` results.
///
/// A lane is analysed when it is shown, not when the session opens: feeding a
/// judge for all fifty lanes of a large session costs hundreds of megabytes
/// nobody asked for.
public actor SessionHost {
  /// What the window gets back: the recording, and the analysis of the lane it
  /// is showing.
  public struct Loaded: Sendable {
    public let recording: Recording
    public let lane: LaneID
    public let analysis: LaneAnalysis
    public let hints: ModelWindowHints
  }

  private let feed: any SessionFeed
  private var open: (any OpenSession)?
  private var analyses: [LaneID: LaneAnalysis] = [:]
  /// Every block's detail read so far, by lane, with the hash of the block it
  /// was read for. A live lane gains blocks at every request, and reading the
  /// ones it already had again would cost the whole file every time.
  private var details: [LaneID: [SegmentID: KnownDetail]] = [:]

  private struct KnownDetail {
    let hash: UInt64
    let detail: BlockDetail?
  }

  public init(feed: any SessionFeed) {
    self.feed = feed
  }

  public func load(
    _ session: SessionRef, lane: LaneID = .main, hints: ModelWindowHints
  ) throws -> Loaded {
    // The old session goes first. Holding it while the new one is read makes
    // the peak two sessions, which on this machine is most of a gigabyte.
    open = nil
    analyses = [:]
    details = [:]
    try Task.checkCancellation()
    let opened = try feed.open(session, hints: hints)
    try Task.checkCancellation()
    open = opened
    return try assemble(opened, lane: lane, hints: hints)
  }

  /// Reads whatever the session has gained. Nil when it gained nothing.
  public func refresh(lane: LaneID, hints: ModelWindowHints) throws -> Loaded? {
    guard let open else { return nil }
    guard try open.refresh() else { return nil }
    analyses = [:]
    return try assemble(open, lane: lane, hints: hints)
  }

  /// Analyses a lane the first time it is shown.
  public func show(lane: LaneID, hints: ModelWindowHints) throws -> Loaded? {
    guard let open else { return nil }
    return try assemble(open, lane: lane, hints: hints)
  }

  /// A block's recorded text, or nil when the transcript has none.
  public func text(of segment: SegmentID, lane: LaneID) -> String? {
    open?.content(of: segment, lane: lane)?.text
  }

  /// The first line of every typed prompt of a lane, shortened, by the
  /// prompt's block. Transcript text, read back here off the main actor the
  /// way a block's text is, for the prompt rows to show and nothing to keep.
  public func promptLines(lane: LaneID) -> [SegmentID: String] {
    guard let open, let found = open.captured.recording.lane(lane) else { return [:] }
    return PromptLine.lines(of: found) { open.content(of: $0, lane: lane) }
  }

  /// What every block of a lane is about, for the ones that say, by block.
  /// Transcript text, read back here off the main actor like the prompt
  /// lines. A block is read once: one whose slot now holds other content is
  /// read again.
  public func blockDetails(lane: LaneID) -> [SegmentID: BlockDetail] {
    guard let open, let found = open.captured.recording.lane(lane) else { return [:] }
    var known = details[lane] ?? [:]
    let missing = found.segments.filter { known[$0.id]?.hash != $0.contentHash }
    if !missing.isEmpty {
      let read = open.details(of: missing.map(\.id), lane: lane)
      for segment in missing {
        known[segment.id] = KnownDetail(hash: segment.contentHash, detail: read[segment.id])
      }
      details[lane] = known
    }
    var shown: [SegmentID: BlockDetail] = [:]
    for segment in found.segments { shown[segment.id] = known[segment.id]?.detail }
    return shown
  }

  private func assemble(
    _ open: any OpenSession, lane: LaneID, hints: ModelWindowHints
  ) throws -> Loaded {
    let captured = open.captured
    var hints = hints
    for lane in captured.recording.lanes { hints.observe(lane) }
    let wanted =
      captured.recording.lane(lane)?.id ?? captured.recording.mainLane?.id ?? .main
    guard let found = captured.recording.lane(wanted) else {
      throw CaptureError.noSuchSession(captured.recording.sessionID)
    }
    let analysis: LaneAnalysis
    if let known = analyses[wanted] {
      analysis = known
    } else {
      analysis = LaneAnalysis(
        session: captured.recording.sessionID,
        lane: found,
        references: open.references(of: wanted)
      )
      analyses[wanted] = analysis
    }
    return Loaded(
      recording: captured.recording, lane: wanted, analysis: analysis, hints: hints)
  }
}
