import Foundation
import ScopeCore
import Testing

@testable import ScopeUI

@Suite("Liveness")
@MainActor
struct LivenessTests {
  private func settle() async {
    for _ in 0..<8 { await Task.yield() }
  }

  @Test("a write just now is live, and stays live for the window")
  func write() async {
    let clock = HeldClock()
    let liveness = Liveness(clock: clock)
    let now = Date()
    liveness.saw(activity: now, now: now)
    #expect(liveness.isLive)
    await settle()
    #expect(clock.waited == [Liveness.window])
  }

  @Test("it drops by itself when the window runs out")
  func drops() async {
    let clock = HeldClock()
    let liveness = Liveness(clock: clock)
    liveness.saw(activity: Date())
    clock.release()
    await settle()
    #expect(!liveness.isLive)
  }

  @Test("a session idle longer than the window is not live at all")
  func alreadyOld() async {
    let clock = HeldClock()
    let liveness = Liveness(clock: clock)
    let now = Date()
    liveness.saw(activity: now.addingTimeInterval(-Liveness.window - 1), now: now)
    #expect(!liveness.isLive)
    await settle()
    #expect(clock.waited.isEmpty)
  }

  @Test("a session part way through its window waits only for what is left")
  func partWay() async {
    let clock = HeldClock()
    let liveness = Liveness(clock: clock)
    let now = Date()
    liveness.saw(activity: now.addingTimeInterval(-60), now: now)
    #expect(liveness.isLive)
    await settle()
    #expect(clock.waited.count == 1)
    #expect(abs((clock.waited.first ?? 0) - (Liveness.window - 60)) < 0.001)
  }

  @Test("another write re-arms the wait rather than adding one")
  func rearms() async {
    let clock = HeldClock()
    let liveness = Liveness(clock: clock)
    let now = Date()
    liveness.saw(activity: now.addingTimeInterval(-60), now: now)
    await settle()
    liveness.saw(activity: now, now: now)
    await settle()
    #expect(liveness.isLive)
    #expect(clock.waited.count == 2)
    #expect(clock.waited.last == Liveness.window)
    clock.release()
    await settle()
    #expect(!liveness.isLive)
  }

  @Test("clearing stops everything and says nothing is live")
  func cleared() async {
    let clock = HeldClock()
    let liveness = Liveness(clock: clock)
    liveness.saw(activity: Date())
    liveness.clear()
    #expect(!liveness.isLive)
    clock.release()
    await settle()
    #expect(!liveness.isLive)
  }

  @Test("a session read from an old file is not live")
  func oldFile() async {
    let clock = HeldClock()
    let model = InstrumentModel(
      feed: RecordingFeed(recordings: [SyntheticRecording.make()]), clock: clock)
    model.reloadSessions()
    await model.settle()
    model.focus(session: model.list.entries.first?.id)
    await model.settle()
    await settle()
    // The test feed dates its sessions in 1970.
    #expect(!model.liveness.isLive)
    #expect(StatusReading.make(from: model)?.isLive == false)
    #expect(clock.waited.isEmpty)
  }
}
