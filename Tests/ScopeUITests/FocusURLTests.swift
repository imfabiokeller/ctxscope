import Foundation
import ScopeCapture
import ScopeConnect
import ScopeCore
import Testing

@testable import ScopeUI

/// A feed the machine can gain a session on between two scans, which is what
/// `/ctxscope` in a brand-new project directory looks like.
private final class ArrivingFeed: SessionFeed, @unchecked Sendable {
  let recording: Recording
  /// Set before the scan that is meant to find it.
  var extra: String?
  /// How long a scan takes. A scan of this machine is most of a second, which
  /// is long enough for somebody to pick a session while it runs.
  var seconds: Double = 0

  init(recording: Recording) {
    self.recording = recording
  }

  func sessions(reusing known: [String: SessionRef]) throws -> [SessionRef] {
    // Off the main actor, in the detached task the scan runs in.
    if seconds > 0 { Thread.sleep(forTimeInterval: seconds) }
    var refs = [ref("newer", ago: 0), ref("older", ago: 1)]
    if let extra { refs.append(ref(extra, ago: 2)) }
    return refs
  }

  private func ref(_ id: String, ago: Double) -> SessionRef {
    SessionRef(
      id: id, project: "/p", url: GrowingFeed.nowhere(id), title: id,
      lastActivity: Date().addingTimeInterval(-ago), byteSize: 0, isLive: ago == 0)
  }

  func open(_ session: SessionRef, hints: ModelWindowHints) throws -> any OpenSession {
    GrowingSession(session: session, full: recording, requests: 20)
  }
}

/// A `show` URL naming an id this machine does not have used to take the focus
/// away: the window went on showing the old session, hook events from it were
/// dropped, and the next scan wiped the focus for good.
@Suite("a show URL that names an unknown id")
@MainActor
struct FocusURLTests {
  private func model() async -> (InstrumentModel, ArrivingFeed) {
    let feed = ArrivingFeed(recording: SyntheticRecording.make())
    let model = InstrumentModel(feed: feed)
    model.focus(session: "newer")
    model.start()
    await model.settle()
    return (model, feed)
  }

  private func show(_ text: String) throws -> ScopeURL.Action {
    try #require(URL(string: text).flatMap(ScopeURL.parse))
  }

  @Test("an id that is not an id at all is a failed substitution")
  func typoInTheURL() throws {
    // The placeholder itself, which is what a shell that did not substitute
    // passes, and anything else with a character an id cannot hold.
    #expect(
      ScopeURL.parse(URL(string: "ctxscope://show?session=%24%7BCLAUDE_SESSION_ID%7D")!)
        == .show(session: nil))
    #expect(try show("ctxscope://show?session=not%20an%20id") == .show(session: nil))
    #expect(try show("ctxscope://show?session=a/b") == .show(session: nil))
    #expect(try show("ctxscope://show?session=") == .show(session: nil))
    #expect(try show("ctxscope://show?session=older") == .show(session: "older"))
    // Both halves of the rule are the same rule.
    #expect(ScopeURL.show(session: "a b") == "ctxscope://show")
    #expect(ScopeURL.valid("a b") == nil)
    #expect(ScopeURL.valid(String(repeating: "a", count: 200)) == nil)
  }

  @Test("a typo keeps the focus that works and shows it")
  func typoKeepsTheFocus() async throws {
    let (model, _) = await model()
    #expect(model.recording?.sessionID == "newer")

    model.open(try show("ctxscope://show?session=nto-a-session"))
    await model.settle()
    #expect(model.list.focused == "newer")
    #expect(model.recording?.sessionID == "newer")
    // And the focused session's events still arrive.
    model.liveness.saw(activity: Date())
    model.apply(HookEvent(kind: .sessionEnd, sessionID: "newer"))
    await model.settle()
    #expect(!model.liveness.isLive)
  }

  @Test("a stale link does not wipe the focus, this scan or the next")
  func staleLink() async throws {
    let (model, _) = await model()
    model.open(try show("ctxscope://show?session=a-session-that-ended-last-week"))
    await model.settle()
    #expect(model.list.focused == "newer")

    // The scan that comes with the next write says the same thing.
    model.reloadSessions()
    await model.settle()
    #expect(model.list.focused == "newer")
    #expect(model.recording?.sessionID == "newer")
  }

  @Test("a session made since the last scan is found and focused")
  func brandNewSession() async throws {
    let (model, feed) = await model()
    feed.extra = "brand-new"
    model.open(try show("ctxscope://show?session=brand-new"))
    await model.settle()
    #expect(model.list.focused == "brand-new")
    #expect(model.recording?.sessionID == "brand-new")
  }

  /// The scan that looks for an unknown id takes as long as a scan takes. A
  /// session picked while it runs is the newer answer, and the scan landing
  /// afterwards used to overwrite it.
  @Test("a session picked while a scan runs is the one that stays")
  func aChoiceBeatsAPendingScan() async throws {
    let (model, feed) = await model()
    feed.extra = "brand-new"
    feed.seconds = 0.3

    model.open(try show("ctxscope://show?session=brand-new"))
    // The menu, or another /ctxscope, while that scan is still running.
    model.focus(session: "older")
    #expect(model.list.focused == "older")

    await model.settle()
    #expect(model.list.focused == "older", "a scan that landed late moved the focus")
    #expect(model.recording?.sessionID == "older")

    // And the id it was looking for is not still waiting to be found.
    model.reloadSessions()
    await model.settle()
    #expect(model.list.focused == "older")
  }

  @Test("a show with no id takes the newest session, once")
  func noID() async throws {
    let (model, _) = await model()
    model.focus(session: "older")
    await model.settle()
    model.open(try show("ctxscope://show"))
    await model.settle()
    #expect(model.list.focused == "newer")
  }
}
