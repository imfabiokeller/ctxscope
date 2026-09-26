internal import Foundation
public import ScopeCapture
public import ScopeCore

public actor SessionHost {
  public struct Loaded: Sendable {
    public let recording: Recording
    public let lane: LaneID
    public let analysis: LaneAnalysis
    public let hints: ModelWindowHints
  }

  private let feed: any SessionFeed
  private var open: (any OpenSession)?
  private var analyses: [LaneID: LaneAnalysis] = [:]
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
    // The old session goes first: holding both while reading doubles peak memory.
    open = nil
    analyses = [:]
    details = [:]
    try Task.checkCancellation()
    let opened = try feed.open(session, hints: hints)
    try Task.checkCancellation()
    open = opened
    return try assemble(opened, lane: lane, hints: hints)
  }

  public func refresh(lane: LaneID, hints: ModelWindowHints) throws -> Loaded? {
    guard let open else { return nil }
    guard try open.refresh() else { return nil }
    analyses = [:]
    return try assemble(open, lane: lane, hints: hints)
  }

  public func show(lane: LaneID, hints: ModelWindowHints) throws -> Loaded? {
    guard let open else { return nil }
    return try assemble(open, lane: lane, hints: hints)
  }

  public func text(of segment: SegmentID, lane: LaneID) -> String? {
    open?.content(of: segment, lane: lane)?.text
  }

  public func promptLines(lane: LaneID) -> [SegmentID: String] {
    guard let open, let found = open.captured.recording.lane(lane) else { return [:] }
    return PromptLine.lines(of: found) { open.content(of: $0, lane: lane) }
  }

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
