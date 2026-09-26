package import Foundation

package struct ConnectService {
  package let home: ClaudeHome
  private let files: any FileStore

  package init(home: ClaudeHome, files: any FileStore = DiskFiles()) {
    self.home = home
    self.files = files
  }

  package struct Status: Sendable, Equatable {
    package let hasSettings: Bool
    package let ports: [UInt16]
    package let events: Set<String>
    package let skill: InstalledSkill
    package let hasBackup: Bool
    package let blocked: String?
    package let hasStaleWake: Bool

    package var hasSkill: Bool { skill != .none }

    package var port: UInt16? {
      let unique = Set(ports)
      return unique.count == 1 ? unique.first : nil
    }

    package var isConnected: Bool { !ports.isEmpty }

    package func needsReconnect(listening: UInt16?) -> Bool {
      isConnected && (isPartial || hasStaleWake || port != listening)
    }
    package var isPartial: Bool {
      isConnected && (events != Set(HookWiring.allEvents) || port == nil)
    }

    package var retired: [String] {
      events.subtracting(HookWiring.allEvents).sorted()
    }
  }

  package enum InstalledSkill: Sendable, Equatable {
    case none
    case ours
    case edited
  }

  package enum Change: Sendable, Equatable {
    case connect(port: UInt16)
    case disconnect
  }

  package struct Plan: Sendable {
    package let change: Change
    package let settings: Data?
    package let removesSettings: Bool
    package let skill: SkillChange
    package let backup: Data?
    package let basis: Data?

    package var isEmpty: Bool {
      !changesSettings && (skill == .none || skill == .keepEdited)
    }

    package var changesSettings: Bool { removesSettings || settings != basis }

    // A function, not a stored value: diffing a large file is slow, so the panel
    // runs it off the main actor.
    package func diff() -> String {
      TextDiff.text(from: basis ?? Data(), to: settings ?? Data())
    }
  }

  package enum SkillChange: Sendable, Equatable {
    case none
    case install
    case remove
    case keepEdited
  }

  package func status() throws -> Status {
    let settings = try files.data(at: home.settings)
    return Status(
      hasSettings: settings != nil,
      ports: try settings.map { try SettingsEdit.installedPorts($0) } ?? [],
      events: try settings.map { try SettingsEdit.installedEvents($0) } ?? [],
      skill: installedSkill(),
      hasBackup: files.exists(home.backup),
      blocked: settings.flatMap {
        HookWiring.blocker(in: $0, port: try? SettingsEdit.installedPorts($0).first)
      },
      hasStaleWake: try settings.map { try SettingsEdit.hasStaleWake($0) } ?? false
    )
  }

  package func plan(_ change: Change) throws -> Plan {
    switch change {
    case .connect(let port): try connectPlan(port: port)
    case .disconnect: try disconnectPlan()
    }
  }

  private func connectPlan(port: UInt16) throws -> Plan {
    try files.checkWritable(home.settings)
    try files.checkWritable(home.skill)
    let current = try files.data(at: home.settings)
    if let current, !SettingsEdit.isBlank(current) { try WriteGuard.check(readable: current) }
    let next = try SettingsEdit.connected(current, port: port)
    try WriteGuard.check(
      current, backup: try files.data(at: home.backup), becomes: next)
    // Safety: a SKILL.md somebody wrote themselves is never written over.
    let skill: SkillChange =
      switch installedSkill() {
      case .none: .install
      case .ours: .none
      case .edited: .keepEdited
      }
    return Plan(
      change: .connect(port: port),
      settings: next,
      removesSettings: false,
      skill: skill,
      // Written once: a second connect keeps the first backup, the file undo restores.
      backup: files.exists(home.backup) ? nil : current,
      basis: current
    )
  }

  private func disconnectPlan() throws -> Plan {
    try files.checkWritable(home.settings)
    guard let current = try files.data(at: home.settings) else {
      return Plan(
        change: .disconnect, settings: nil, removesSettings: false,
        skill: try skillRemoval(), backup: nil, basis: nil)
    }
    try WriteGuard.check(readable: current)
    let backup = try files.data(at: home.backup)
    let restored = try restored(current, backup: backup)
    // Safety: an original goes back as it was, but an edited file must stay
    // readable by the harness or nothing is written.
    if case .edited(let next) = restored, !WriteGuard.isWellFormed(next) {
      throw Refusal.wouldNotBeReadable
    }
    let next = restored.settings
    return Plan(
      change: .disconnect,
      settings: next,
      removesSettings: next == nil,
      skill: try skillRemoval(),
      backup: nil,
      basis: current
    )
  }

  private func restored(_ current: Data, backup: Data?) throws -> Restored {
    if let port = try SettingsEdit.installedPorts(current).first {
      if let backup, (try? SettingsEdit.connected(backup, port: port)) == current {
        return .original(backup)
      }
      if backup == nil, (try? SettingsEdit.connected(nil, port: port)) == current {
        return .original(nil)
      }
    }
    return .edited(try SettingsEdit.disconnected(current, original: backup))
  }

  private enum Restored {
    case original(Data?)
    case edited(Data)

    var settings: Data? {
      switch self {
      case .original(let data): data
      case .edited(let data): data
      }
    }
  }

  private func installedSkill() -> InstalledSkill {
    guard let found = (try? files.data(at: home.skill)) ?? nil else { return .none }
    return found == ConnectSkill.data ? .ours : .edited
  }

  private func skillRemoval() throws -> SkillChange {
    switch installedSkill() {
    case .none: .none
    case .ours: .remove
    case .edited: .keepEdited
    }
  }

  package func apply(_ plan: Plan) throws {
    // Checks come before the read to keep the race window small. The backup
    // write must stay after the `moved` check, or undo would trust a stale backup.
    try files.checkWritable(home.settings)
    let mode = files.mode(of: home.settings)
    let exists = files.exists(home.settings)
    let current = try files.data(at: home.settings)
    guard current == plan.basis else { throw Refusal.moved }
    // Safety: the backup is the settings file under another name, never wider.
    if plan.backup != nil {
      try files.write(current ?? Data(), to: home.backup, mode: mode ?? 0o600)
    }
    if plan.removesSettings {
      try files.remove(home.settings)
    } else if let settings = plan.settings {
      // Safety: a settings file ctxscope creates starts at 0600; an existing
      // one keeps its mode.
      try files.write(settings, to: home.settings, mode: exists ? nil : 0o600)
    }
    switch plan.skill {
    case .none, .keepEdited: break
    case .install: try files.write(ConnectSkill.data, to: home.skill)
    case .remove:
      try files.remove(home.skill)
      if files.isEmptyDirectory(home.skillFolder) { try files.remove(home.skillFolder) }
    }
    if case .disconnect = plan.change { try files.remove(home.backup) }
  }
}
