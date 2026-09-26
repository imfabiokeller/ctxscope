package import Foundation

/// Connecting ctxscope to Claude Code, and disconnecting it again.
///
/// Every write is planned first: the plan carries the exact diff, and nothing
/// reaches the disk until the plan is applied. The settings file as it was
/// before the first write is kept beside it, so undo can put the original
/// bytes back rather than a file that merely parses the same.
package struct ConnectService {
  package let home: ClaudeHome
  private let files: any FileStore

  package init(home: ClaudeHome, files: any FileStore = DiskFiles()) {
    self.home = home
    self.files = files
  }

  /// What ctxscope has and has not written.
  package struct Status: Sendable, Equatable {
    package let hasSettings: Bool
    /// The ports our entries point at, one per event when all is well.
    package let ports: [UInt16]
    package let events: Set<String>
    package let skill: InstalledSkill
    package let hasBackup: Bool
    /// One line about a setting that would stop the hooks running, or nil.
    package let blocked: String?
    /// True when the entry that starts ctxscope is one an older version
    /// wrote. It reads as connected and would turn an off ctxscope on.
    package let hasStaleWake: Bool

    package var hasSkill: Bool { skill != .none }

    /// The one port our entries agree on, when they agree.
    package var port: UInt16? {
      let unique = Set(ports)
      return unique.count == 1 ? unique.first : nil
    }

    package var isConnected: Bool { !ports.isEmpty }

    /// True when the entries in the file would not reach a ctxscope listening
    /// on this port: some are missing, they disagree, or they name another
    /// port. One rule, so the panel and the menu bar cannot say different
    /// things.
    package func needsReconnect(listening: UInt16?) -> Bool {
      isConnected && (isPartial || hasStaleWake || port != listening)
    }
    /// True when the entries in the file are not the set ctxscope writes now:
    /// one is missing, one is left over from an older version, or they name
    /// more than one port. Connecting again is what fixes it.
    package var isPartial: Bool {
      isConnected && (events != Set(HookWiring.allEvents) || port == nil)
    }

    /// Entries of ours for events ctxscope does not ask for any more. A file
    /// written before the hooks were cut down carries five.
    package var retired: [String] {
      events.subtracting(HookWiring.allEvents).sorted()
    }
  }

  /// What is at `skills/ctxscope/SKILL.md`.
  package enum InstalledSkill: Sendable, Equatable {
    case none
    case ours
    /// Somebody wrote their own. It is left where it is.
    case edited
  }

  package enum Change: Sendable, Equatable {
    case connect(port: UInt16)
    case disconnect
  }

  /// What one change would do. `settings` nil means the file goes, which is
  /// what undo does to a settings file ctxscope created.
  package struct Plan: Sendable {
    package let change: Change
    package let settings: Data?
    package let removesSettings: Bool
    package let skill: SkillChange
    package let backup: Data?
    /// The settings file this plan was worked out from. Nil means there was
    /// none. The file is read again before anything is written and compared
    /// with this, so a plan that has gone stale writes nothing.
    package let basis: Data?

    package var isEmpty: Bool {
      !changesSettings && (skill == .none || skill == .keepEdited)
    }

    package var changesSettings: Bool { removesSettings || settings != basis }

    /// The lines this would change. Not stored: a diff of a large file costs
    /// real time, and the panel works it out off the main actor from the two
    /// values above rather than holding up a frame for it.
    package func diff() -> String {
      TextDiff.text(from: basis ?? Data(), to: settings ?? Data())
    }
  }

  package enum SkillChange: Sendable, Equatable {
    case none
    case install
    case remove
    /// Somebody wrote their own SKILL.md where ours was. It stays where it is,
    /// and the panel says so rather than throwing away their work.
    case keepEdited
  }

  // MARK: reading

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

  // MARK: planning

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
    // A SKILL.md somebody wrote themselves is theirs. It is left where it is
    // rather than written over, and the panel says so.
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
      // Written once, before the first change, and only when there is a file
      // to copy. A second connect leaves the first backup alone, because that
      // is the file undo has to restore.
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
    // What was there before goes back as it was, whatever it was. What was
    // edited has to be a file the harness reads.
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

  /// The file without ctxscope in it.
  ///
  /// When the file is exactly what ctxscope last wrote, what was there before
  /// goes back byte for byte: the backup, or no file at all when there was
  /// none. A file that holds only whitespace is a file, not an absence, and
  /// comes back with its whitespace. When something else changed the file
  /// since, only our entries come out and the rest stays where it is.
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

  /// Which way the file came back: as it was before ctxscope wrote anything,
  /// or with our entries taken out of a file somebody else has changed since.
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

  // MARK: writing

  /// Writes what the plan says, after checking that the file has not moved
  /// under it. A panel can sit open while Claude Code writes an allow rule
  /// into the same file, and a plan worked out before that would put the file
  /// back the way it was.
  package func apply(_ plan: Plan) throws {
    // Everything that can be asked is asked before the file is read, so that
    // as little as possible happens between reading it and replacing it. What
    // is left in that window is the backup write, and it has to stay there:
    // a backup written before the check would be the file as it was when the
    // plan was worked out, and undo would then trust it.
    try files.checkWritable(home.settings)
    let mode = files.mode(of: home.settings)
    let exists = files.exists(home.settings)
    let current = try files.data(at: home.settings)
    guard current == plan.basis else { throw Refusal.moved }
    // The backup is the person's settings file under another name, so it is
    // written with the settings file's own permissions and never wider.
    if plan.backup != nil {
      try files.write(current ?? Data(), to: home.backup, mode: mode ?? 0o600)
    }
    if plan.removesSettings {
      try files.remove(home.settings)
    } else if let settings = plan.settings {
      // A settings file ctxscope creates says what a Claude session may do,
      // so it starts at 0600, which no other account can read. One that is
      // already there keeps whatever mode it was given.
      try files.write(settings, to: home.settings, mode: exists ? nil : 0o600)
    }
    switch plan.skill {
    case .none, .keepEdited: break
    case .install: try files.write(ConnectSkill.data, to: home.skill)
    case .remove:
      // Only the file ctxscope wrote. Anything somebody put beside it is
      // theirs, and the folder goes only when nothing is left in it.
      try files.remove(home.skill)
      if files.isEmptyDirectory(home.skillFolder) { try files.remove(home.skillFolder) }
    }
    // The backup has done its job once the settings file is back.
    if case .disconnect = plan.change { try files.remove(home.backup) }
  }
}
