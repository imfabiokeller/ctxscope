import ScopeCore
import Testing

@testable import ScopeUI

/// The item is a picture and a number, so what it says out loud is the only
/// thing a screen reader has. It had no name at all, and no tooltip until a
/// session was in focus.
@Suite("what the item says")
struct StatusVoiceTests {
  private func reading(isLive: Bool) -> StatusReading {
    StatusReading(isLive: isLive, totalTokens: 142_600, window: 200_000)
  }

  @Test("every state has a name, a value and a tooltip")
  func everyState() {
    #expect(StatusVoice.name == "ctxscope")
    for reading in [nil, reading(isLive: true), reading(isLive: false)] {
      #expect(!StatusVoice.value(reading).isEmpty)
      #expect(StatusVoice.tooltip(reading).hasPrefix("ctxscope, "))
    }
  }

  @Test("with nothing in focus it says so rather than saying nothing")
  func nothingInFocus() {
    #expect(StatusVoice.value(nil) == "no session in focus")
    #expect(StatusVoice.tooltip(nil) == "ctxscope, no session in focus")
  }

  @Test("a session brings its size and its window")
  func aSession() {
    #expect(StatusVoice.value(reading(isLive: true)) == "142.6k of 200k")
    #expect(StatusVoice.tooltip(reading(isLive: true)) == "ctxscope, 142.6k of 200k")
    // An idle session says so, because the bar drops its number and only
    // dims the mark.
    #expect(StatusVoice.value(reading(isLive: false)) == "142.6k of 200k, idle")
  }
}
