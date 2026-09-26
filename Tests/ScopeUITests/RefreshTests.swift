import Foundation
import ScopeCore
import Testing

@testable import ScopeUI

@Suite("Refresh")
@MainActor
struct RefreshTests {
  private func model(startAt: Int = 20) async -> InstrumentModel {
    let model = InstrumentModel(
      feed: GrowingFeed(recording: SyntheticRecording.make(), startAt: startAt))
    model.reloadSessions()
    await model.settle()
    model.focus(session: model.list.entries.first?.id)
    await model.settle()
    return model
  }

  @Test("a lane that grows marks the session live")
  func growthIsLiveness() async throws {
    let model = await model()
    model.liveness.clear()
    #expect(!model.liveness.isLive)
    model.refresh()
    await model.settle()
    #expect(model.liveness.isLive)
    #expect(StatusReading.make(from: model)?.isLive == true)
    model.liveness.clear()
    model.refresh()
    await model.settle()
    model.refresh()
    await model.settle()
    model.refresh()
    await model.settle()
    let settled = model.analysis?.requestCount
    model.liveness.clear()
    model.refresh()
    await model.settle()
    if model.analysis?.requestCount == settled { #expect(!model.liveness.isLive) }
  }

  @Test("a lane that grows carries the playhead with it while it is at the end")
  func followsTheEnd() async throws {
    let model = await model()
    let first = try #require(model.analysis)
    #expect(first.requestCount == 20)
    #expect(model.playhead == first.lastRequest)
    #expect(model.isAtLatest)

    model.refresh()
    await model.settle()
    let grown = try #require(model.analysis)
    #expect(grown.requestCount == 25)
    #expect(model.playhead == grown.lastRequest)
    #expect(model.isAtLatest)
  }

  @Test("a playhead somebody moved stays where they put it")
  func keepsAScrubbedPlayhead() async throws {
    let model = await model()
    model.move(playheadTo: 5)
    #expect(!model.isAtLatest)

    model.refresh()
    await model.settle()
    #expect(model.playhead == 5)
    #expect(!model.isAtLatest)
    #expect(model.analysis?.requestCount == 25)
  }

  @Test("a burst that arrives during a read is read afterwards, not dropped")
  func refreshDuringRefresh() async throws {
    let model = await model()
    #expect(model.analysis?.requestCount == 20)
    model.refresh()
    model.refresh()
    await model.settle()
    #expect(model.analysis?.requestCount == 30)
    #expect(!model.needsRefresh)
  }

  @Test("a refresh that gains nothing changes nothing")
  func idleRefresh() async throws {
    let model = await model(startAt: 65)
    let before = model.analysis?.requestCount
    model.refresh()
    await model.settle()
    #expect(model.analysis?.requestCount == before)
  }

  @Test("stopping during a load leaves nothing behind, and starting again works")
  func stopDuringLoad() async throws {
    let model = InstrumentModel(
      feed: GrowingFeed(recording: SyntheticRecording.make(), startAt: 20))
    model.focus(session: SyntheticRecording.make().sessionID)
    model.reloadSessions()
    model.stop()
    #expect(!model.isLoading)

    model.start()
    await model.settle()
    #expect(!model.isLoading)
    #expect(model.analysis != nil)
    #expect(model.recording != nil)

    model.refresh()
    await model.settle()
    #expect(model.analysis?.requestCount == 25)
    model.stop()
  }

  @Test("settle returns even when a task was cancelled without clearing itself")
  func settleTerminates() async throws {
    let model = await model()
    model.reloadSessions()
    model.focus(session: model.list.entries.first?.id)
    model.stop()
    await model.settle()
    #expect(!model.isLoading)
  }

  /// Segment ids are slot numbers, so one session's selected id usually exists in another.
  @Test("switching session drops the selection and its text")
  func sessionSwitch() async throws {
    let first = SyntheticRecording.make()
    let second = SyntheticRecording.make(SyntheticRecording.Options(seed: 29))
    let model = InstrumentModel(
      feed: RecordingFeed(
        recordings: [first, second],
        judgeInputs: [
          first.sessionID: [.main: SyntheticJudge.input(for: first.mainLane!)],
          second.sessionID: [.main: SyntheticJudge.input(for: second.mainLane!)],
        ]
      )
    )
    model.reloadSessions()
    await model.settle()
    model.focus(session: model.list.entries.first?.id)
    await model.settle()
    let analysis = try #require(model.analysis)
    let segment = try #require(analysis.lane.segments.first { $0.isAssessable })
    model.select(segment.id)
    await model.settle()
    #expect(model.selectedText != nil)

    model.focus(session: second.sessionID)
    #expect(model.selection == nil)
    #expect(model.selectedText == nil)
    await model.settle()
    #expect(model.recording?.sessionID == second.sessionID)
    #expect(model.selection == nil)
    #expect(model.selectedText == nil)
  }

  @Test("switching lanes moves the playhead and drops the selection")
  func laneSwitch() async throws {
    let recording = SyntheticRecording.make()
    guard let main = recording.mainLane else { return }
    let second = Lane(
      id: LaneID("agent-1"), agentType: "explore", window: main.window,
      segments: Array(main.segments.prefix(40)),
      snapshots: Array(main.snapshots.prefix(9)))
    let two = Recording(
      sessionID: recording.sessionID, project: recording.project, title: recording.title,
      lanes: [main, second])
    let model = InstrumentModel(feed: GrowingFeed(recording: two, startAt: 65))
    model.reloadSessions()
    await model.settle()
    model.focus(session: model.list.entries.first?.id)
    await model.settle()
    #expect(model.lane == .main)
    model.select(model.analysis?.lane.segments.first?.id)
    #expect(model.selection != nil)

    model.show(lane: LaneID("agent-1"))
    await model.settle()
    #expect(model.lane == LaneID("agent-1"))
    #expect(model.selection == nil)
    #expect(model.analysis?.requestCount == 9)
    #expect(model.playhead == 8)
  }
}
