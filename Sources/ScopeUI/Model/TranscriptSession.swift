internal import Foundation
internal import ScopeCapture
internal import ScopeCore

final class TranscriptSession: OpenSession {
  let session: SessionRef
  private(set) var captured: CapturedSession
  private var capture: SessionCapture
  private var judges: [LaneID: LexicalJudge] = [:]
  private var fedSegments: [LaneID: Int] = [:]
  private var fedConsumers: [LaneID: Int] = [:]
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
    // The judge memoizes inside the copy, so the copy goes back.
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
      // The newest consumer is fed again because a response grows as it streams.
      // Safe: a judge records each reference once.
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
