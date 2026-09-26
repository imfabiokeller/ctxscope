import ScopeCore
import Testing

@testable import ScopeUI

@Suite("when the item fades")
struct StatusMotionTests {
  private func face(tokens: Int = 142_600, isLive: Bool = true) -> StatusFace {
    StatusFace(
      reading: StatusReading(
        isLive: isLive, totalTokens: tokens, window: 200_000, fill: Double(tokens) / 200_000,
        breaksCache: false))
  }

  private func fades(
    from previous: StatusFace?, to face: StatusFace, reduceMotion: Bool = false
  ) -> Bool {
    StatusMotion.crossFades(from: previous, to: face, reduceMotion: reduceMotion)
  }

  @Test("a new size, the session going quiet and focus changing all fade")
  func changes() {
    let before = face()
    #expect(fades(from: before, to: face(tokens: 151_000)))
    #expect(fades(from: before, to: face(isLive: false)))
    #expect(fades(from: before, to: StatusFace(reading: nil)))
  }

  @Test("a request that leaves the number as it was is nothing to fade")
  func sameNumber() {
    #expect(!fades(from: face(tokens: 142_600), to: face(tokens: 142_700)))
  }

  @Test("nothing changing is nothing to fade")
  func idle() {
    #expect(!fades(from: face(), to: face()))
  }

  @Test("the first picture has nothing to fade from")
  func firstDraw() {
    #expect(!fades(from: nil, to: face()))
  }

  @Test("Reduce Motion means no motion")
  func reduceMotion() {
    #expect(!fades(from: face(), to: face(isLive: false), reduceMotion: true))
  }

  @Test("it is one fifth of a second, once")
  func duration() {
    #expect(StatusMotion.seconds > 0.1)
    #expect(StatusMotion.seconds <= 0.25)
  }
}
