import ScopeCore
import Testing

@testable import ScopeUI

@Suite("what the item says")
struct StatusVoiceTests {
  private func reading(isLive: Bool, breaksCache: Bool = false) -> StatusReading {
    StatusReading(
      isLive: isLive, totalTokens: 142_600, window: 200_000, fill: 0.713, breaksCache: breaksCache)
  }

  @Test("every state has a name, a value and a tooltip")
  func everyState() {
    #expect(StatusVoice.name == "ctxscope")
    for reading in [
      nil, reading(isLive: true), reading(isLive: false), reading(isLive: true, breaksCache: true),
    ] {
      #expect(!StatusVoice.value(reading).isEmpty)
      #expect(StatusVoice.tooltip(reading).hasPrefix("ctxscope, "))
    }
  }

  @Test("with nothing in focus it says so rather than saying nothing")
  func nothingInFocus() {
    #expect(StatusVoice.value(nil) == "no session in focus")
    #expect(StatusVoice.tooltip(nil) == "ctxscope, no session in focus")
  }

  @Test("a session brings its size, its window and its fill")
  func aSession() {
    #expect(StatusVoice.value(reading(isLive: true)) == "142.6k of 200k, 71% full")
    #expect(StatusVoice.tooltip(reading(isLive: true)) == "ctxscope, 142.6k of 200k, 71% full")
    #expect(StatusVoice.value(reading(isLive: false)) == "142.6k of 200k, 71% full, idle")
  }

  @Test("a cache break on the newest request is said while the session is live")
  func cacheBreak() {
    #expect(
      StatusVoice.value(reading(isLive: true, breaksCache: true))
        == "142.6k of 200k, 71% full, cache break on the last request")
    #expect(
      StatusVoice.value(reading(isLive: false, breaksCache: true))
        == "142.6k of 200k, 71% full, idle")
  }
}
