import Foundation
import ScopeConnect
import ScopeCore
import Testing

@testable import ScopeUI

@Suite("what a hook event does")
@MainActor
struct HookEventWiringTests {
  private func model(focus: String? = "newer") async -> InstrumentModel {
    let model = InstrumentModel(feed: GrowingFeed.two(recording: SyntheticRecording.make()))
    model.focus(session: focus)
    model.start()
    await model.settle()
    return model
  }

  private func event(_ kind: HookEvent.Kind, _ session: String) -> HookEvent {
    HookEvent(kind: kind, sessionID: session)
  }

  @Test("the focused session is the one that is shown")
  func focused() async throws {
    let model = await model()
    #expect(model.list.focused == "newer")
    #expect(model.recording?.sessionID == "newer")

    model.focus(session: "older")
    await model.settle()
    #expect(model.recording?.sessionID == "older")
  }

  /// The one event ctxscope asks for. A transcript that has stopped growing
  /// looks exactly like a session that has ended, and the difference is three
  /// minutes of the item saying a session is live when it is over.
  @Test("the session ending drops it at once")
  func sessionEnd() async throws {
    let model = await model()
    model.liveness.saw(activity: Date())
    #expect(model.liveness.isLive)

    model.apply(event(.sessionEnd, "newer"))
    await model.settle()
    #expect(!model.liveness.isLive)
    // It is still the focused session: ending is not unfocusing.
    #expect(model.list.focused == "newer")
  }

  @Test("an event from any other session is read and dropped")
  func otherSessions() async throws {
    let model = await model()
    let before = try #require(model.analysis).requestCount
    model.liveness.clear()

    for kind in HookEvent.Kind.allCases {
      model.apply(event(kind, "older"))
      await model.settle()
      #expect(!model.liveness.isLive, "\(kind.rawValue) marked something live")
      #expect(model.recording?.sessionID == "newer", "\(kind.rawValue) moved the view")
      #expect(try #require(model.analysis).requestCount == before, "\(kind.rawValue) read a lane")
    }
    #expect(model.list.focused == "newer")
  }

  @Test("with nothing focused the window shows nothing and hooks do nothing")
  func nothingFocused() async throws {
    let model = await model(focus: nil)
    #expect(model.list.focused == nil)
    #expect(model.analysis == nil)
    #expect(model.recording == nil)
    #expect(StatusReading.make(from: model) == nil)

    for kind in HookEvent.Kind.allCases {
      model.apply(event(kind, "newer"))
      await model.settle()
    }
    #expect(model.analysis == nil)
    #expect(!model.liveness.isLive)
  }

  @Test("a focus this machine no longer has is let go")
  func focusGone() async throws {
    let model = await model(focus: "a session that ended long ago")
    #expect(model.list.focused == nil)
    #expect(model.analysis == nil)
  }

  @Test("a model that has been turned off does nothing with a hook event")
  func turnedOff() async throws {
    let model = await model()
    model.stop()
    #expect(!model.isOn)
    model.liveness.saw(activity: Date())

    model.apply(event(.sessionEnd, "newer"))
    await model.settle()
    #expect(model.liveness.isLive, "a hook cleared liveness while off")
    #expect(model.recording != nil)

    model.start()
    await model.settle()
    model.apply(event(.sessionEnd, "newer"))
    await model.settle()
    #expect(!model.liveness.isLive)
  }

  @Test("focusing while off reads nothing, and starting reads it")
  func focusWhileOff() async throws {
    let model = await model(focus: nil)
    model.stop()
    model.focus(session: "older")
    await model.settle()
    #expect(model.list.focused == "older")
    #expect(model.recording == nil, "a stopped model read a transcript")

    model.start()
    await model.settle()
    #expect(model.recording?.sessionID == "older")
  }

  @Test("the focused session is remembered by whoever owns the model")
  func remembered() async throws {
    let model = await model(focus: nil)
    var seen: [String?] = []
    model.onFocusChanged = { seen.append($0) }
    model.focus(session: "older")
    await model.settle()
    model.focus(session: "newer")
    await model.settle()
    model.focus(session: nil)
    await model.settle()
    #expect(seen == ["older", "newer", nil])
  }

  @Test("a ctxscope URL focuses a session")
  func urls() async throws {
    let model = await model(focus: nil)
    #expect(parse("ctxscope://show?session=older") == .show(session: "older"))
    #expect(parse("ctxscope://show") == .show(session: nil))
    #expect(parse("ctxscope://wake") == .wake)
    #expect(parse("ctxscope:wake") == .wake)
    #expect(parse(ScopeURL.wake) == .wake)
    #expect(parse("ctxscope://open") == nil)
    #expect(parse("https://example.com/show") == nil)
    #expect(ScopeURL.show(session: "a b") == "ctxscope://show")
    #expect(
      ScopeURL.show(session: ScopeURL.sessionPlaceholder)
        == "ctxscope://show?session=${CLAUDE_SESSION_ID}")

    model.open(try #require(parse("ctxscope://show?session=older")))
    await model.settle()
    #expect(model.recording?.sessionID == "older")

    // Without an id the substitution failed. The session written to most
    // recently is taken once, rather than followed from then on.
    model.open(try #require(parse("ctxscope://show")))
    await model.settle()
    #expect(model.list.focused == "newer")

    // Waking focuses nothing and opens nothing.
    model.open(.wake)
    await model.settle()
    #expect(model.list.focused == "newer")
  }

  private func parse(_ text: String) -> ScopeURL.Action? {
    URL(string: text).flatMap(ScopeURL.parse)
  }
}
