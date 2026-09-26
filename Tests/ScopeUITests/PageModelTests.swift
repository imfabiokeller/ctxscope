import Foundation
import ScopeCore
import Testing

@testable import ScopeUI

@Suite("The window's pages")
@MainActor
struct PageModelTests {
  private func model() async -> InstrumentModel {
    let recording = SyntheticRecording.make()
    let model = InstrumentModel(
      feed: RecordingFeed(
        recordings: [recording],
        judgeInputs: [recording.sessionID: [.main: ModelTests.judgeInput(recording)]]))
    model.reloadSessions()
    await model.settle()
    model.focus(session: model.list.entries.first?.id)
    await model.settle()
    return model
  }

  @Test("the figures follow the playhead and nothing else works them out")
  func figures() async throws {
    let model = await model()
    let analysis = try #require(model.analysis)
    #expect(model.figures?.request == analysis.lastRequest)
    model.move(playheadTo: 10)
    #expect(model.figures?.request == 10)
    #expect(model.figures?.column.request == 10)
    #expect(model.figures?.cost?.request == 10)
  }

  @Test("a block is shown in the timeline in the task it entered in")
  func showInTimeline() async throws {
    let model = await model()
    let analysis = try #require(model.analysis)
    let segment = try #require(
      analysis.lane.segments.first { $0.born > 20 && $0.kind == .results })
    model.showInTimeline(block: segment.id)
    #expect(model.page == .timeline)
    #expect(model.selection == segment.id)
    let expected = analysis.prompts.prompt(containing: segment.born)?.number
    #expect(expected != nil)
    #expect(model.selectedPrompt == expected)
  }

  @Test("a request is shown in the context page with the playhead on it")
  func showContext() async throws {
    let model = await model()
    model.page = .timeline
    model.showContext(at: 5)
    #expect(model.page == .context)
    #expect(model.playhead == 5)
    #expect(model.isAtLatest == false)
  }

  @Test("prompt lines are read after the lane is shown")
  func promptLines() async throws {
    let recording = SyntheticRecording.make()
    let lane = try #require(recording.mainLane)
    let prompt = try #require(lane.prompts.first)
    let model = InstrumentModel(
      feed: RecordingFeed(
        recordings: [recording],
        contents: [recording.sessionID: [prompt: "Fix the retry loop\nand more"]]))
    model.reloadSessions()
    await model.settle()
    model.focus(session: model.list.entries.first?.id)
    await model.settle()
    #expect(model.promptLines[prompt] == "Fix the retry loop")
  }
}
