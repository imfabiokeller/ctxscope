internal import Foundation
package import ScopeConnect

/// What the Connect panel shows and what its one button does.
///
/// What is connected, and the exact diff before anything is written. The
/// button is Connect whenever something would change to make the wiring
/// right, and Disconnect once everything is already in place, so there is
/// never a second one to choose between.
@MainActor
@Observable
package final class ConnectModel {
  package enum Hooks: Sendable, Equatable {
    case off
    case on(port: UInt16)
    /// The settings name a port, and ctxscope is not answering on it.
    case unreachable(port: UInt16)
    /// Some of our entries are there and some are not.
    case partial
    /// Our entries are all there, and so are entries for events ctxscope does
    /// not ask for any more.
    case older

    package var text: String {
      switch self {
      case .off: "Not connected"
      case .on(let port): "Connected, port \(port)"
      case .unreachable(let port): "Connected, ctxscope not on port \(port)"
      case .partial: "Half connected"
      case .older: "Connected, by an older ctxscope"
      }
    }
  }

  package private(set) var hooks: Hooks = .off
  /// What is at skills/ctxscope/SKILL.md.
  package private(set) var skill = ConnectService.InstalledSkill.none
  /// One short line about the copy of the settings file ctxscope keeps.
  package private(set) var backupNote: String?
  /// What the button would write. Nil when the settings file cannot be read.
  package private(set) var plan: ConnectService.Plan?
  /// The lines that plan would change, worked out off the main actor: a diff
  /// of a large settings file is not something a frame should wait for.
  package private(set) var diff = ""
  /// Set when reading or writing failed, in the words the failure used.
  package private(set) var failure: String?
  /// One line about what just happened, in plain words. Cleared by the next
  /// read.
  package private(set) var done: String?

  private let service: ConnectService
  /// The port the app's own listener has, or nil when it has none.
  private var listening: UInt16?
  @ObservationIgnored private var work: Task<Void, Never>?

  package init(home: ClaudeHome, listening: UInt16? = nil) {
    service = ConnectService(home: home)
    self.listening = listening
    read()
  }

  /// The port ctxscope would write: the one it is listening on, so the hooks
  /// point at the listener that is actually running.
  private var port: UInt16 {
    listening ?? (try? service.status())?.port ?? HookWiring.defaultPort
  }

  /// Connect while anything would change to make the wiring right, and
  /// Disconnect once it all is.
  package var buttonTitle: String { plan?.change == .disconnect ? "Disconnect" : "Connect" }

  /// One line under the Hooks row: a setting that stops every hook, or a port
  /// that no longer matches, and nothing at all when everything is where it
  /// should be.
  package var hint: String? {
    if let blocked { return "\(blocked)." }
    guard case .unreachable = hooks else { return nil }
    guard let listening else { return "ctxscope has no port. Open it again." }
    return "ctxscope is listening on port \(listening). Connect again to point the hooks at it."
  }

  /// A setting in the file that would stop the hooks running whatever is
  /// written under `hooks`. Not something ctxscope writes or removes.
  package private(set) var blocked: String?

  /// True when the hooks in the settings file would not reach this ctxscope.
  /// The menu bar says so too, because the panel is not open when it matters.
  package var needsReconnect: Bool {
    (try? service.status())?.needsReconnect(listening: listening) ?? false
  }

  /// Waits for the diff, for a caller that needs it before it can do
  /// anything: the snapshot renderer, and a test.
  package func settle() async {
    while let pending = work {
      await pending.value
      if work == pending { work = nil }
    }
  }

  package func listener(port: UInt16?) {
    listening = port
    read()
  }

  package func read() {
    done = nil
    do {
      // The plan first, because it is the one that says in plain words why a
      // settings file cannot be touched.
      let connect = try service.plan(.connect(port: port))
      plan = connect.isEmpty ? try service.plan(.disconnect) : connect
      let status = try service.status()
      hooks = state(of: status)
      skill = status.skill
      blocked = status.blocked
      backupNote = note(about: status)
      failure = nil
      show(diffOf: plan)
    } catch {
      hooks = .off
      skill = .none
      blocked = nil
      backupNote = nil
      plan = nil
      diff = ""
      work?.cancel()
      failure = message(for: error)
    }
  }

  private func show(diffOf plan: ConnectService.Plan?) {
    work?.cancel()
    diff = ""
    guard let plan else { return }
    work = Task { [weak self] in
      let text = await Task.detached(priority: .userInitiated) { plan.diff() }.value
      guard let self, !Task.isCancelled else { return }
      diff = text
      work = nil
    }
  }

  /// Plain words. A settings file is not a place to show a Swift error in.
  private func message(for error: any Error) -> String {
    (error as? Refusal)?.description ?? "the settings file could not be written"
  }

  /// The backup is a copy of the settings file under another name.
  /// It is one line, because a panel that explains itself is a panel nobody
  /// reads.
  private func note(about status: ConnectService.Status) -> String? {
    if status.hasBackup { return "A copy of the settings file is kept beside it." }
    guard plan?.backup != nil else { return nil }
    return "A copy of the settings file will be kept beside it."
  }

  private func state(of status: ConnectService.Status) -> Hooks {
    guard status.isConnected else { return .off }
    if !status.retired.isEmpty { return .older }
    guard !status.isPartial, let port = status.port else { return .partial }
    return listening == port ? .on(port: port) : .unreachable(port: port)
  }

  /// Applies what the panel is showing.
  ///
  /// The settings file is read again first. A panel can sit open while Claude
  /// Code writes into the same file, and a plan worked out before that would
  /// put the file back the way it was, so it writes nothing, works the change
  /// out again, and says so in one line.
  package func act() {
    guard let plan else { return }
    apply(plan)
  }

  private func apply(_ plan: ConnectService.Plan) {
    do {
      try service.apply(plan)
    } catch Refusal.moved {
      read()
      done = "The settings file changed. Nothing was written, and this is the new diff."
      return
    } catch {
      let said = message(for: error)
      read()
      failure = said
      return
    }
    read()
    done = plan.change == .disconnect ? "Removed." : "Written."
  }
}
