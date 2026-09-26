import Foundation
import ScopeCapture
import ScopeCore
import Testing

@testable import ScopeUI

@Suite("prompt lines from the host")
struct PromptLineHostTests {
  @Test("the host reads back one line per typed prompt of the lane it is asked about")
  func lines() async throws {
    let recording = SyntheticRecording.make()
    let lane = try #require(recording.mainLane)
    let corpus = SyntheticJudge.corpus(for: lane)
    let feed = RecordingFeed(
      recordings: [recording],
      judgeInputs: [recording.sessionID: [.main: corpus.input]],
      contents: [recording.sessionID: corpus.texts])
    let host = SessionHost(feed: feed)
    let session = try #require(try feed.sessions(reusing: [:]).first)
    _ = try await host.load(session, hints: ModelWindowHints())
    let lines = await host.promptLines(lane: .main)
    #expect(!lines.isEmpty)
    #expect(Set(lines.keys) == Set(lane.prompts.filter { corpus.texts[$0] != nil }))
    #expect(lines.values.allSatisfy { !$0.contains("\n") && $0.count <= PromptLine.limit })
    #expect(await host.promptLines(lane: LaneID("nobody")).isEmpty)
  }
}
