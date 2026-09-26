import Foundation
import ScopeCapture
import ScopeCore
import Testing

@testable import ScopeUI

/// A session whose subagent lane grows while its main lane stands still,
/// which is what a subagent working for five minutes looks like.
private final class LaneGrowing: OpenSession, @unchecked Sendable {
  let session: SessionRef
  private(set) var captured: CapturedSession
  private let full: Recording
  private var laneRequests: Int

  init(session: SessionRef, full: Recording, laneRequests: Int = 1) {
    self.session = session
    self.full = full
    self.laneRequests = laneRequests
    captured = Self.cut(full, lane: laneRequests)
  }

  /// Every refresh gives the subagent lane one more request and the main lane
  /// none.
  func refresh() throws -> Bool {
    guard let main = full.mainLane, laneRequests < main.snapshots.count else { return false }
    laneRequests += 1
    captured = Self.cut(full, lane: laneRequests)
    return true
  }

  func references(of lane: LaneID) -> ReferenceReport {
    ReferenceReport(method: LexicalJudge().method, findings: [])
  }

  func content(of segment: SegmentID, lane: LaneID) -> SegmentContent? { nil }
  func details(of segments: [SegmentID], lane: LaneID) -> [SegmentID: BlockDetail] { [:] }

  static func cut(_ recording: Recording, lane requests: Int) -> CapturedSession {
    guard let main = recording.mainLane else {
      return CapturedSession(recording: recording, judgeInputs: [:])
    }
    let subagent = Lane(
      id: LaneID("agent-1"),
      agentType: "explore",
      window: main.window,
      segments: main.segments.filter { $0.born < requests },
      snapshots: Array(main.snapshots.prefix(requests))
    )
    return CapturedSession(
      recording: Recording(
        sessionID: recording.sessionID, project: recording.project, title: recording.title,
        lanes: [main, subagent]),
      judgeInputs: [:])
  }
}

private struct LaneFeed: SessionFeed {
  let recording: Recording
  let url: URL

  func sessions(reusing known: [String: SessionRef]) throws -> [SessionRef] {
    [
      SessionRef(
        id: recording.sessionID, project: "/p", url: url, title: "one",
        lastActivity: Date(), byteSize: 0, isLive: true)
    ]
  }

  func open(_ session: SessionRef, hints: ModelWindowHints) throws -> any OpenSession {
    LaneGrowing(session: session, full: recording)
  }
}

/// A subagent is where the interesting part of a session often is, and it was
/// invisible: only the `subagents` directory was watched, never the lane files
/// in it, so a lane could grow for minutes while the item dimmed to idle.
@Suite("a subagent at work")
@MainActor
struct SubagentWatchTests {
  private struct Home {
    let transcript: URL
    let lanes: URL
    let lane: URL
  }

  private func home(withLane: Bool) throws -> Home {
    let project = FileManager.default.temporaryDirectory
      .appending(path: "ctxscope-lane-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let transcript = project.appending(path: "session.jsonl")
    try Data("{}\n".utf8).write(to: transcript)
    // The layout the adapter reads: <project>/<session>/subagents/<lane>.jsonl
    let lanes = project.appending(path: "session").appending(path: "subagents")
    let lane = lanes.appending(path: "agent-1.jsonl")
    if withLane {
      try FileManager.default.createDirectory(at: lanes, withIntermediateDirectories: true)
      try Data("{}\n".utf8).write(to: lane)
    }
    return Home(transcript: transcript, lanes: lanes, lane: lane)
  }

  /// The directory listing resolves symlinks and the temporary directory is
  /// one, so both sides are compared resolved.
  private func watches(_ model: InstrumentModel, _ url: URL) -> Bool {
    model.watchedPaths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
      .contains(url.resolvingSymlinksInPath().path)
  }

  private func model(_ home: Home, _ recording: Recording) async -> InstrumentModel {
    let model = InstrumentModel(feed: LaneFeed(recording: recording, url: home.transcript))
    model.focus(session: recording.sessionID)
    model.start()
    await model.settle()
    return model
  }

  @Test("every lane file is watched, and so is the directory it sits in")
  func lanesAreWatched() async throws {
    let home = try home(withLane: true)
    defer { try? FileManager.default.removeItem(at: home.transcript.deletingLastPathComponent()) }
    let model = await model(home, SyntheticRecording.make())

    #expect(watches(model, home.transcript))
    #expect(watches(model, home.lanes))
    #expect(watches(model, home.lane))
    model.stop()
  }

  @Test("a lane that grows while the main transcript is quiet is the session working")
  func laneGrowthIsActivity() async throws {
    let home = try home(withLane: true)
    defer { try? FileManager.default.removeItem(at: home.transcript.deletingLastPathComponent()) }
    let recording = SyntheticRecording.make()
    let model = await model(home, recording)
    let before = model.recording?.lane(LaneID("agent-1"))?.snapshots.count ?? 0
    model.liveness.clear()

    // Nothing is written to the main transcript at all.
    let stamp = try FileManager.default.attributesOfItem(atPath: home.transcript.path)
    let handle = try FileHandle(forWritingTo: home.lane)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("{}\n".utf8))
    try handle.close()

    try await WatcherTests.wait { model.liveness.isLive }
    #expect(model.liveness.isLive, "a subagent at work left the item dimming to idle")
    #expect((model.recording?.lane(LaneID("agent-1"))?.snapshots.count ?? 0) > before)
    #expect(
      try FileManager.default.attributesOfItem(atPath: home.transcript.path)[.modificationDate]
        as? Date == stamp[.modificationDate] as? Date)
    model.stop()
  }

  @Test("a subagents directory that appears later is watched")
  func directoryAppearsLater() async throws {
    let home = try home(withLane: false)
    defer { try? FileManager.default.removeItem(at: home.transcript.deletingLastPathComponent()) }
    let model = await model(home, SyntheticRecording.make())
    #expect(!watches(model, home.lanes))

    // The agent spawns a subagent: the directory and its lane appear in the
    // project directory, and nothing is written to the main transcript.
    try FileManager.default.createDirectory(at: home.lanes, withIntermediateDirectories: true)
    try Data("{}\n".utf8).write(to: home.lane)

    try await WatcherTests.wait { watches(model, home.lane) }
    #expect(watches(model, home.lanes))
    #expect(watches(model, home.lane))
    model.stop()
  }
}
