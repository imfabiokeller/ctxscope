import Foundation
import ScopeCapture
import ScopeCore

@testable import ScopeUI

final class GrowingSession: OpenSession, @unchecked Sendable {
  let session: SessionRef
  private(set) var captured: CapturedSession
  private let full: Recording
  private let step: Int
  private var shown: Int

  init(session: SessionRef, full: Recording, requests: Int, step: Int = 5) {
    self.session = session
    self.full = full
    self.step = step
    shown = requests
    captured = Self.cut(full, to: requests, id: session.id)
  }

  func refresh() throws -> Bool {
    guard let lane = full.mainLane, shown < lane.snapshots.count else { return false }
    shown = min(lane.snapshots.count, shown + step)
    captured = Self.cut(full, to: shown, id: session.id)
    return true
  }

  func references(of lane: LaneID) -> ReferenceReport {
    ReferenceReport(method: LexicalJudge().method, findings: [])
  }

  func content(of segment: SegmentID, lane: LaneID) -> SegmentContent? { nil }
  func details(of segments: [SegmentID], lane: LaneID) -> [SegmentID: BlockDetail] { [:] }

  static func cut(_ recording: Recording, to requests: Int, id: String) -> CapturedSession {
    let lanes = recording.lanes.map { lane in
      Lane(
        id: lane.id,
        agentType: lane.agentType,
        window: lane.window,
        segments: lane.segments.filter { $0.born < requests },
        snapshots: Array(lane.snapshots.prefix(requests)),
        compactions: lane.compactions.filter { $0.atRequest < requests },
        events: lane.events.filter { $0.request < requests },
        stats: lane.stats
      )
    }
    return CapturedSession(
      recording: Recording(
        sessionID: id, project: recording.project, title: recording.title, lanes: lanes),
      judgeInputs: [:]
    )
  }
}

struct GrowingFeed: SessionFeed {
  let recording: Recording
  let refs: [SessionRef]
  var startAt = 20

  /// At a path that does not exist on purpose: a real path would have the watcher firing and
  /// the session growing on its own.
  init(recording: Recording, startAt: Int = 20) {
    self.recording = recording
    self.startAt = startAt
    refs = [
      SessionRef(
        id: recording.sessionID, project: recording.project,
        url: Self.nowhere(recording.sessionID), title: recording.title,
        lastActivity: Date(), byteSize: 0, isLive: true)
    ]
  }

  static func nowhere(_ id: String) -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "ctxscope-nowhere-\(UUID().uuidString)")
      .appending(path: "\(id).jsonl")
  }

  init(recording: Recording, refs: [SessionRef], startAt: Int = 20) {
    self.recording = recording
    self.refs = refs
    self.startAt = startAt
  }

  static func two(recording: Recording, ids: [String] = ["newer", "older"]) -> GrowingFeed {
    GrowingFeed(
      recording: recording,
      refs: ids.enumerated().map { slot, id in
        SessionRef(
          id: id, project: "/p", url: nowhere(id), title: id,
          lastActivity: Date().addingTimeInterval(Double(-slot)), byteSize: 0,
          isLive: slot == 0)
      })
  }

  func sessions(reusing known: [String: SessionRef]) throws -> [SessionRef] { refs }

  func open(_ session: SessionRef, hints: ModelWindowHints) throws -> any OpenSession {
    GrowingSession(session: session, full: recording, requests: startAt)
  }
}
