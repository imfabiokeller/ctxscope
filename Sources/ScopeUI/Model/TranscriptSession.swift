internal import Foundation
internal import ScopeCapture
internal import ScopeCore

/// One transcript session held open, with a judge per lane fed as the session
/// grows.
///
/// The judge is appended to, never re-fed: the work per
/// request has to be proportional to that request, and following a live 1M session is
/// the case that proves it.
final class TranscriptSession: OpenSession {
  let session: SessionRef
  private(set) var captured: CapturedSession
  private var capture: SessionCapture
  private var judges: [LaneID: LexicalJudge] = [:]
  /// How much of each lane's judge input has already been fed.
  private var fedSegments: [LaneID: Int] = [:]
  private var fedConsumers: [LaneID: Int] = [:]
  /// Lanes anybody has asked about. A judge is built for a lane when the lane
  /// is shown: feeding one for all fifty lanes of a large session costs
  /// hundreds of megabytes nobody asked for.
  private var wanted: Set<LaneID> = [.main]

  var windowHints: ModelWindowHints {
    get { capture.windowHints }
    set { capture.windowHints = newValue }
  }

  init(capture: SessionCapture, session: SessionRef) {
    self.capture = capture
    self.session = session
    captured = capture.current()
    feedJudges()
  }

  @discardableResult
  func refresh() throws -> Bool {
    // Given up on between batches when nobody is waiting for it any more. A
    // user who picks another session should not wait out the one they left.
    let result = try capture.refresh { Task.isCancelled }
    guard result.newLines > 0 || result.skippedLines > 0 else { return false }
    captured = capture.current()
    feedJudges()
    return true
  }

  func references(of lane: LaneID) -> ReferenceReport {
    if wanted.insert(lane).inserted { feedJudges() }
    guard var judge = judges[lane] else {
      return ReferenceReport(method: Self.makeJudge().method, findings: [])
    }
    let report = judge.report()
    // The judge keeps what it worked out, so put it back rather than throwing
    // the memo away with the copy.
    judges[lane] = judge
    return report
  }

  func content(of segment: SegmentID, lane: LaneID) -> SegmentContent? {
    capture.content(of: segment, lane: lane)
  }

  func details(of segments: [SegmentID], lane: LaneID) -> [SegmentID: BlockDetail] {
    capture.details(of: segments, lane: lane)
  }

  private static func makeJudge() -> LexicalJudge {
    LexicalJudge(segmentShingleCap: CapturedSession.segmentShingleCap)
  }

  /// Hands each judge only what it has not seen.
  ///
  /// The newest consumer is always fed again, because a response grows as it
  /// streams. That is safe: a judge marks matched shingles in a set and only
  /// records a reference request once, so feeding the same consumer twice
  /// cannot count anything twice. A lane whose input shrank, which a rewind
  /// can do, is built again from scratch.
  private func feedJudges() {
    for (lane, input) in captured.judgeInputs where wanted.contains(lane) {
      var judge = judges[lane] ?? Self.makeJudge()
      var segments = fedSegments[lane] ?? 0
      var consumers = fedConsumers[lane] ?? 0
      if input.segments.count < segments || input.consumers.count < consumers {
        judge = Self.makeJudge()
        segments = 0
        consumers = 0
      }
      let from = max(0, consumers - 1)
      guard input.segments.count > segments || input.consumers.count > from else { continue }
      for segment in input.segments[segments...] { judge.add(segment: segment) }
      for consumer in input.consumers[from...] { judge.add(consumer: consumer) }
      judges[lane] = judge
      fedSegments[lane] = input.segments.count
      fedConsumers[lane] = input.consumers.count
    }
  }
}
