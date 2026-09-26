import Foundation
import ScopeCapture
import ScopeCore
import Testing

@testable import ScopeUI

/// A block is called by its tool and what it did wherever the window names
/// it, and by its label until that is known.
@Suite("block names")
@MainActor
struct BlockNamesTests {
  static let detail = BlockDetail(head: "Read", detail: "src/api/client.ts")

  @Test("a detail makes the name, and a block without one keeps its label")
  func name() throws {
    let lane = try #require(SyntheticRecording.make().mainLane)
    let first = try #require(lane.segments.first)
    let names = BlockNames([first.id: Self.detail])
    #expect(names.name(of: first) == "Read · src/api/client.ts")
    let second = try #require(lane.segments.dropFirst().first)
    #expect(names.name(of: second) == second.label)
  }

  @Test("the rows, the strip, the sidebar and the largest addition all use the name")
  func everywhere() throws {
    let analysis = ContextPresenterTests.analysis()
    let figures = analysis.figures(at: analysis.lastRequest)
    let plain = ContextPresenter.page(analysis, figures)
    let row = try #require(plain.blocks.rows.first { $0.kind == .results })
    let names = BlockNames([row.id: Self.detail])
    let page = ContextPresenter.page(analysis, figures, selection: row.id, names: names)
    #expect(page.blocks.rows.first { $0.id == row.id }?.label == "Read · src/api/client.ts")
    #expect(page.strip.slices.first { $0.id == row.id }?.label == "Read · src/api/client.ts")
    #expect(page.inspector?.title == "Read · src/api/client.ts")
    let found = ContextPresenter.page(analysis, figures, query: "client.ts", names: names)
    #expect(found.blocks.rows.map(\.id) == [row.id])

    let lane = analysis.lane
    let prompt = try #require(analysis.prompts.prompts.first { $0.largestAdded != nil })
    let largest = try #require(prompt.largestAdded)
    let timeline = TimelinePresenter.present(
      lane: lane, costs: analysis.costs, cache: analysis.cache, prompts: analysis.prompts,
      order: analysis.readingOrder, promptLines: [:], names: BlockNames([largest: Self.detail]),
      selectedPrompt: prompt.number)
    let fact = try #require(timeline.detail?.facts.first { $0.term == "Largest addition" })
    #expect(fact.value == "Read · src/api/client.ts")
    let slot = try #require(lane.segments.firstIndex { $0.id == largest })
    #expect(timeline.chart.blocks[slot].label == "Read · src/api/client.ts")
  }

  @Test("the model reads the names back from the host once a lane is shown")
  func fromTheHost() async throws {
    let recording = SyntheticRecording.make()
    let lane = try #require(recording.mainLane)
    let block = try #require(lane.segments.last)
    let feed = RecordingFeed(
      recordings: [recording], details: [recording.sessionID: [block.id: Self.detail]])
    let model = InstrumentModel(feed: feed)
    model.reloadSessions()
    await model.settle()
    model.focus(session: recording.sessionID)
    await model.settle()
    #expect(model.blockNames.name(of: block) == "Read · src/api/client.ts")
    #expect(model.blockNames.details.count == 1)
  }
}
