internal import Foundation
public import ScopeCapture
public import ScopeCore

/// A feed over recordings that are already in hand.
///
/// This is how the snapshot renderer and the tests drive the same views the
/// app drives, with no transcript anywhere near them. It is production code
/// because the synthetic recording is how the 1M token scale is shown at all.
public struct RecordingFeed: SessionFeed {
  private let recordings: [Recording]
  private let judgeInputs: [String: [LaneID: JudgeInput]]
  private let contents: [String: [SegmentID: String]]
  private let details: [String: [SegmentID: BlockDetail]]

  public init(
    recordings: [Recording],
    judgeInputs: [String: [LaneID: JudgeInput]] = [:],
    contents: [String: [SegmentID: String]] = [:],
    details: [String: [SegmentID: BlockDetail]] = [:]
  ) {
    self.recordings = recordings
    self.judgeInputs = judgeInputs
    self.contents = contents
    self.details = details
  }

  public func sessions(reusing known: [String: SessionRef]) throws -> [SessionRef] {
    recordings.enumerated().map { index, recording in
      SessionRef(
        id: recording.sessionID,
        project: recording.project,
        url: URL(fileURLWithPath: "/dev/null"),
        title: recording.title,
        // Newest first, and the first one counts as live so that following the
        // active session picks it.
        lastActivity: Date(timeIntervalSince1970: Double(1_000_000 - index)),
        byteSize: 0,
        isLive: index == 0
      )
    }
  }

  public func open(_ session: SessionRef, hints: ModelWindowHints) throws -> any OpenSession {
    guard let recording = recordings.first(where: { $0.sessionID == session.id }) else {
      throw CaptureError.noSuchSession(session.id)
    }
    return HeldRecording(
      session: session,
      captured: CapturedSession(
        recording: recording, judgeInputs: judgeInputs[session.id] ?? [:]),
      contents: contents[session.id] ?? [:],
      details: details[session.id] ?? [:]
    )
  }
}

/// One recording held open. Nothing grows, so a refresh has nothing to do.
final class HeldRecording: OpenSession {
  let session: SessionRef
  let captured: CapturedSession
  private let contents: [SegmentID: String]
  private let details: [SegmentID: BlockDetail]
  private var judges: [LaneID: LexicalJudge] = [:]

  init(
    session: SessionRef, captured: CapturedSession, contents: [SegmentID: String],
    details: [SegmentID: BlockDetail]
  ) {
    self.session = session
    self.captured = captured
    self.contents = contents
    self.details = details
    for (lane, input) in captured.judgeInputs {
      var judge = LexicalJudge(segmentShingleCap: CapturedSession.segmentShingleCap)
      judge.add(input)
      judges[lane] = judge
    }
  }

  func refresh() throws -> Bool { false }

  func references(of lane: LaneID) -> ReferenceReport {
    guard var judge = judges[lane] else {
      return ReferenceReport(method: LexicalJudge().method, findings: [])
    }
    let report = judge.report()
    judges[lane] = judge
    return report
  }

  func content(of segment: SegmentID, lane: LaneID) -> SegmentContent? {
    guard let text = contents[segment],
      let found = captured.recording.lane(lane)?.segments.first(where: { $0.id == segment })
    else { return nil }
    return SegmentContent(
      segment: segment, band: found.band, label: found.label, text: text)
  }

  func details(of segments: [SegmentID], lane: LaneID) -> [SegmentID: BlockDetail] {
    guard captured.recording.lane(lane) != nil else { return [:] }
    return details.filter { segments.contains($0.key) }
  }
}
