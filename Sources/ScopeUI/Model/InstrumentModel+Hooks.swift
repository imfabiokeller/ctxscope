internal import Foundation
package import ScopeConnect

/// What a hook event does to the instrument, and nothing more.
///
/// One thing, for the focused session: that it has ended. Everything else a
/// hook could say, the file watcher says on its own within a fraction of a
/// second, from the file the work is written to. The end is the one thing no
/// file says: a transcript that has stopped growing looks exactly like a
/// session that has ended.
///
/// An event from any other session is read and dropped: ctxscope shows the
/// session it was told to show, and nothing on the machine changes that.
extension InstrumentModel {
  package func apply(_ event: HookEvent) {
    // Turned off means turned off. The listener still answers every hook with
    // a 200, so a connected session sees nothing, and nothing here reads a
    // transcript or puts the menu bar item back.
    guard isOn, event.sessionID == list.focused else { return }
    switch event.kind {
    case .sessionEnd:
      liveness.clear()
      reloadSessions()
    }
  }

  /// What a `ctxscope://` URL asks for.
  package func open(_ action: ScopeURL.Action) {
    guard case .show(let session) = action else { return }
    // Without an id the substitution failed, and the session written to most
    // recently is the best guess anybody has. It is taken once, here, rather
    // than followed from then on.
    guard let session else { return focus(session: list.newest?.id) }
    // An id the list does not know is either a session in a project directory
    // nothing has scanned since it was made, or an id this machine does not
    // have at all. A scan says which, and the focus moves only if it is
    // found: a typo or a stale link never takes away a focus that works.
    guard list.entries.contains(where: { $0.id == session }) else {
      return focus(afterScanFinds: session)
    }
    focus(session: session)
  }
}
