import ScopeCore
import Testing

@testable import ScopeUI

@Suite("the menu bar's face")
struct StatusFaceTests {
  private func reading(isLive: Bool, breaksCache: Bool = false) -> StatusReading {
    StatusReading(
      isLive: isLive, totalTokens: 142_600, window: 200_000, fill: 0.713, breaksCache: breaksCache)
  }

  @Test("a live session is the live mark at its fill, and its size")
  func live() {
    #expect(
      StatusFace(reading: reading(isLive: true))
        == StatusFace(state: .live, fill: 17.0 / 24, number: "143k"))
  }

  @Test("a cache break on the newest request splits the cursor, and keeps the size")
  func cacheBreak() {
    #expect(
      StatusFace(reading: reading(isLive: true, breaksCache: true))
        == StatusFace(state: .cacheBreak, fill: 0.713, number: "143k"))
  }

  @Test("an idle session is the idle mark at its fill, with no number")
  func idle() {
    for breaksCache in [false, true] {
      #expect(
        StatusFace(reading: reading(isLive: false, breaksCache: breaksCache))
          == StatusFace(state: .idle, fill: 0.713, number: nil))
    }
  }

  @Test("no session in focus is the empty track, idle, with no number")
  func none() {
    #expect(StatusFace(reading: nil) == StatusFace(state: .idle, fill: 0, number: nil))
  }

  @Test("the face keeps the fill on the glyph's half points")
  func snapped() {
    #expect(StatusFace(state: .live, fill: 0.713, number: nil).fill == 17.0 / 24)
    #expect(
      StatusFace(state: .live, fill: 0.705, number: nil)
        == StatusFace(state: .live, fill: 0.72, number: nil))
  }
}

@Suite("what the menu bar reads")
@MainActor
struct StatusReadingTests {
  private func model(
    focus: Bool, options: SyntheticRecording.Options = .init()
  ) async -> InstrumentModel {
    let recording = SyntheticRecording.make(options)
    let model = InstrumentModel(feed: RecordingFeed(recordings: [recording]))
    model.reloadSessions()
    await model.settle()
    if focus {
      model.focus(session: recording.sessionID)
      await model.settle()
    }
    return model
  }

  @Test("a session in focus reads as its size and fill against its window")
  func focused() async throws {
    let model = await model(focus: true)
    let reading = try #require(StatusReading.make(from: model))
    let analysis = try #require(model.analysis)
    let last = try #require(analysis.tally(at: analysis.lastRequest))
    #expect(reading.totalTokens == last.total.value)
    #expect(reading.fill == last.fill)
    #expect(reading.fill > 0)
    #expect(reading.window == analysis.lane.window.tokens)
    #expect(reading.totalTokens > 0)
  }

  @Test("an older cache break is not the newest request's")
  func olderBreak() async throws {
    let model = await model(focus: true)
    let analysis = try #require(model.analysis)
    #expect(!analysis.cache.busts.isEmpty)
    #expect(try #require(StatusReading.make(from: model)).breaksCache == false)
  }

  @Test("a cache break on the newest request reads as one")
  func newestBreak() async throws {
    let model = await model(focus: true, options: .init(requests: 40, compactAt: nil, bustAt: 40))
    let analysis = try #require(model.analysis)
    #expect(analysis.cache.busts.last?.request == analysis.lastRequest)
    #expect(try #require(StatusReading.make(from: model)).breaksCache)
  }

  @Test("no session in focus reads as nothing")
  func none() async throws {
    let model = await model(focus: false)
    #expect(StatusReading.make(from: model) == nil)
  }

  @Test("an idle session still reads, and says it is idle")
  func idle() async throws {
    let model = await model(focus: true)
    model.liveness.clear()
    let reading = try #require(StatusReading.make(from: model))
    #expect(!reading.isLive)
  }
}
