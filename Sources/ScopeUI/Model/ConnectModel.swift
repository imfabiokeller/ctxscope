internal import Foundation
package import ScopeConnect

@MainActor
@Observable
package final class ConnectModel {
  package enum Hooks: Sendable, Equatable {
    case off
    case on(port: UInt16)
    case unreachable(port: UInt16)
    case partial
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
  package private(set) var skill = ConnectService.InstalledSkill.none
  package private(set) var backupNote: String?
  package private(set) var plan: ConnectService.Plan?
  package private(set) var diff = ""
  package private(set) var failure: String?
  package private(set) var done: String?

  private let service: ConnectService
  private var listening: UInt16?
  @ObservationIgnored private var work: Task<Void, Never>?

  package init(home: ClaudeHome, listening: UInt16? = nil) {
    service = ConnectService(home: home)
    self.listening = listening
    read()
  }

  private var port: UInt16 {
    listening ?? (try? service.status())?.port ?? HookWiring.defaultPort
  }

  package var buttonTitle: String { plan?.change == .disconnect ? "Disconnect" : "Connect" }

  package var hint: String? {
    if let blocked { return "\(blocked)." }
    guard case .unreachable = hooks else { return nil }
    guard let listening else { return "ctxscope has no port. Open it again." }
    return "ctxscope is listening on port \(listening). Connect again to point the hooks at it."
  }

  package private(set) var blocked: String?

  package var needsReconnect: Bool {
    (try? service.status())?.needsReconnect(listening: listening) ?? false
  }

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
      // The plan goes first: it is the call that says why a settings file cannot be touched.
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

  private func message(for error: any Error) -> String {
    (error as? Refusal)?.description ?? "the settings file could not be written"
  }

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
