import Foundation
import ScopeConnect
import ScopeCore
import ScopeUI
import Testing

@testable import ctxscope

@Suite("what a launch does")
@MainActor
struct LaunchTests {
  private func model() -> (InstrumentModel, String) {
    let recording = SyntheticRecording.make()
    return (InstrumentModel(feed: RecordingFeed(recordings: [recording])), recording.sessionID)
  }

  @Test("a launch that is off reads nothing, whatever arrives")
  func offReadsNothing() async throws {
    let (model, session) = model()
    Launch.begin(model: model, focus: session, isOff: true)
    await model.settle()
    #expect(model.list.focused == session, "the focus is kept, it is only not read")
    #expect(model.recording == nil)

    model.apply(HookEvent(kind: .sessionEnd, sessionID: session))
    await model.settle()
    #expect(model.recording == nil, "a hook read a transcript while off")
    #expect(model.analysis == nil)
    #expect(!model.liveness.isLive)
    #expect(model.watchedPaths.isEmpty)
    #expect(StatusReading.make(from: model) == nil)
  }

  @Test("a launch that is on opens the focused session")
  func onOpensIt() async throws {
    let (model, session) = model()
    Launch.begin(model: model, focus: session, isOff: false)
    await model.settle()
    #expect(model.recording?.sessionID == session)
    model.stop()
  }

  @Test("a launch by hand opens the window, and nothing else does")
  func opensTheWindow() {
    #expect(Launch.opensWindow(["/x/ctxscope"]))
    #expect(!Launch.opensWindow(["/x/ctxscope", HookWiring.wokenFlag]))
    #expect(!Launch.opensWindow(["/x/ctxscope", "--print-status"]))
    #expect(!Launch.opensWindow(["/x/ctxscope", "--print-hooks", "/tmp/x"]))
    #expect(!Launch.opensWindow(["/x/ctxscope", "--print-appearance"]))
    #expect(Launch.opensWindow(["/x/ctxscope", HookWiring.wokenFlag, Launch.windowFlag]))
  }

  @Test("turning it on after an off launch opens what was focused all along")
  func onAfterOff() async throws {
    let (model, session) = model()
    Launch.begin(model: model, focus: session, isOff: true)
    await model.settle()
    #expect(model.recording == nil)

    model.start()
    await model.settle()
    #expect(model.recording?.sessionID == session)
    model.stop()
  }
}
