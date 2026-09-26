import Foundation
import ScopeCore
import Testing

@testable import ScopeUI

@Suite("Instrument model")
@MainActor
struct ModelTests {
  private func model() async -> InstrumentModel {
    let big = SyntheticRecording.make(.millionTokenWindow)
    let small = SyntheticRecording.make()
    let model = InstrumentModel(
      feed: RecordingFeed(
        recordings: [small, big],
        judgeInputs: [
          small.sessionID: [.main: Self.judgeInput(small)],
          big.sessionID: [.main: Self.judgeInput(big)],
        ]
      )
    )
    model.reloadSessions()
    await model.settle()
    model.focus(session: model.list.entries.first?.id)
    await model.settle()
    return model
  }

  /// Every second segment referenced at the request after it entered, so the
  /// two encodings have something to show.
  static func judgeInput(_ recording: Recording) -> JudgeInput {
    guard let lane = recording.mainLane else { return JudgeInput() }
    var segments: [JudgedSegment] = []
    var consumers: [JudgedConsumer] = []
    for (index, segment) in lane.segments.enumerated() {
      let hash = UInt64(index &+ 1)
      segments.append(
        JudgedSegment(
          id: segment.id,
          born: segment.born,
          isAssessable: segment.isAssessable,
          isInput: segment.originRequest == nil,
          shingles: segment.isAssessable ? [hash, hash &* 3, hash &* 7] : []
        )
      )
      if index.isMultiple(of: 2) {
        consumers.append(
          JudgedConsumer(
            request: min(segment.born + 1, lane.snapshots.count - 1),
            shingles: [hash, hash &* 3]))
      }
    }
    return JudgeInput(segments: segments, consumers: consumers)
  }

  @Test("the window shows the focused session and nothing else")
  func focus() async throws {
    let model = await model()
    let entries = model.list.entries
    #expect(entries.count == 2)
    #expect(model.recording?.sessionID == entries[0].id)

    model.focus(session: entries[1].id)
    await model.settle()
    #expect(model.list.focused == entries[1].id)
    #expect(model.recording?.sessionID == entries[1].id)

    // Nothing focused is an empty window, not the newest session.
    model.focus(session: nil)
    await model.settle()
    #expect(model.recording == nil)
    #expect(model.analysis == nil)
  }

  @Test("the playhead starts at the newest request and clamps to the lane")
  func playhead() async {
    let model = await model()
    let analysis = model.analysis
    #expect(model.playhead == analysis?.lastRequest)
    #expect(model.isAtLatest)
    model.move(playheadTo: 3)
    #expect(model.playhead == 3)
    #expect(!model.isAtLatest)
    model.move(playheadTo: -20)
    #expect(model.playhead == 0)
    model.move(playheadTo: 10_000)
    #expect(model.playhead == analysis?.lastRequest)
    #expect(model.isAtLatest)
  }

  @Test("a lane is analyzed once, and the numbers add up to the measured total")
  func analysis() async throws {
    let model = await model()
    let analysis = try #require(model.analysis)
    for entry in analysis.tally.perRequest {
      #expect(entry.byBand.reduce(0) { $0 + $1.value } == entry.total.value)
    }
    #expect(analysis.carry.ranked.count == analysis.lane.segments.count)
  }

  @Test("replay walks the playhead forward and stops at the end")
  func replay() async throws {
    let model = await model()
    model.move(playheadTo: 0)
    model.toggleReplay()
    #expect(model.replay.isRunning)
    try await Task.sleep(for: .seconds(Replay.slowInterval * 1.6))
    #expect(model.playhead > 0)
    model.toggleReplay()
    #expect(!model.replay.isRunning)
  }

  @Test("a selected block brings its text, read off the main actor")
  func reader() async throws {
    let model = await model()
    let analysis = try #require(model.analysis)
    let segment = try #require(analysis.lane.segments.first { $0.isAssessable })
    model.select(segment.id)
    await model.settle()
    let content = try #require(model.selectedText)
    #expect(content.segment == segment.id)
    // The fixture feed carries no text, so there is none to show.
    #expect(content.text == nil)
  }

  @Test("export gives back both formats with the same segments")
  func export() async throws {
    let model = await model()
    let json = try #require(model.export(.json))
    let csv = try #require(model.export(.csv))
    #expect(json.count > 100)
    let rows = String(decoding: csv, as: UTF8.self)
      .split(separator: "\n", omittingEmptySubsequences: true)
    #expect(rows.count == (model.analysis?.lane.segments.count ?? 0) + 1)
    #expect(model.exportName(.csv).hasSuffix(".csv"))
  }
}
