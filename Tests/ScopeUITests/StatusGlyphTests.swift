import CoreGraphics
import ScopeCore
import Testing

@testable import ScopeUI

/// The mark in the menu bar: three bars rising left to right, filled with a
/// session in focus and outlined with none.
@Suite("the menu bar mark")
struct StatusGlyphTests {
  @Test("three bars, three points wide, rising, inside a 14 by 12 box")
  func geometry() {
    #expect(StatusGlyph.size == CGSize(width: 14, height: 12))
    let bars = StatusGlyph.bars
    #expect(bars.count == 3)
    #expect(bars.allSatisfy { $0.width == 3 })
    #expect(bars.map(\.height) == [4.5, 7.5, 11])
    // They stand on one base, and every one fits the box with its outline.
    #expect(Set(bars.map(\.maxY)).count == 1)
    let box = CGRect(origin: .zero, size: StatusGlyph.size)
    for bar in bars {
      #expect(box.contains(bar.insetBy(dx: -StatusGlyph.stroke / 2, dy: -StatusGlyph.stroke / 2)))
    }
  }

  @Test("filled bars sit on whole pixels at every scale", arguments: [CGFloat(1), 2, 3])
  func pixels(scale: CGFloat) {
    for bar in StatusGlyph.filled(scale: scale) {
      for edge in [bar.minX, bar.maxX, bar.minY, bar.maxY] {
        #expect((edge * scale).rounded() == edge * scale)
      }
    }
  }

  @Test("at 2x the filled bars are the glyph's own")
  func twoX() {
    #expect(StatusGlyph.filled(scale: 2) == StatusGlyph.bars)
  }
}

/// What the item shows for each state of the session in focus.
@Suite("the menu bar's face")
struct StatusFaceTests {
  @Test("a live session is the filled mark and its size")
  func live() {
    let face = StatusFace(
      reading: StatusReading(isLive: true, totalTokens: 142_600, window: 200_000))
    #expect(face == StatusFace(style: .filled, isDimmed: false, number: "143k"))
  }

  @Test("an idle session is the same mark, dimmed, with no number")
  func idle() {
    let face = StatusFace(
      reading: StatusReading(isLive: false, totalTokens: 142_600, window: 200_000))
    #expect(face == StatusFace(style: .filled, isDimmed: true, number: nil))
  }

  @Test("no session in focus is the outline, at full ink, with no number")
  func none() {
    #expect(StatusFace(reading: nil) == StatusFace(style: .outlined, isDimmed: false, number: nil))
  }
}

/// What the menu bar shows of the session in focus, and what it shows when
/// there is none.
@Suite("what the menu bar reads")
@MainActor
struct StatusReadingTests {
  private func model(focus: Bool) async -> InstrumentModel {
    let recording = SyntheticRecording.make()
    let model = InstrumentModel(feed: RecordingFeed(recordings: [recording]))
    model.reloadSessions()
    await model.settle()
    if focus {
      model.focus(session: recording.sessionID)
      await model.settle()
    }
    return model
  }

  @Test("a session in focus reads as its size against its window")
  func focused() async throws {
    let model = await model(focus: true)
    let reading = try #require(StatusReading.make(from: model))
    let analysis = try #require(model.analysis)
    #expect(reading.totalTokens == analysis.tally(at: analysis.lastRequest)?.total.value)
    #expect(reading.window == analysis.lane.window.tokens)
    #expect(reading.totalTokens > 0)
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
