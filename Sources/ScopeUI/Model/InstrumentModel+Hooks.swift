internal import Foundation
package import ScopeConnect

extension InstrumentModel {
  package func apply(_ event: HookEvent) {
    guard isOn, event.sessionID == list.focused else { return }
    switch event.kind {
    case .sessionEnd:
      liveness.clear()
      reloadSessions()
    }
  }

  package func open(_ action: ScopeURL.Action) {
    guard case .show(let session) = action else { return }
    guard let session else { return focus(session: list.newest?.id) }
    guard list.entries.contains(where: { $0.id == session }) else {
      return focus(afterScanFinds: session)
    }
    focus(session: session)
  }
}
