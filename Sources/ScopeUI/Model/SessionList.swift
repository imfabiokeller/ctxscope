public import Foundation
public import ScopeCapture
public import ScopeCore

/// The session menu: live sessions first, then recent ones, each with
/// project, title and fill, and subagent lanes nested under their parent.
///
/// Exactly one session is focused, and ctxscope shows that one. Nothing here
/// picks a session on its own: focus comes from `/ctxscope` typed in a chat,
/// or from this menu. Everything else on the machine is listed and ignored.
@MainActor
@Observable
public final class SessionList {
  public struct Entry: Sendable, Identifiable {
    public let session: SessionRef
    /// Fill of the main lane, once the session has been opened. Sessions that
    /// have not been opened do not claim a number they do not have.
    public var fill: Double?
    /// The subagent lanes of this session, once it is open.
    public var lanes: [LaneEntry] = []

    public var id: String { session.id }
    public var title: String { session.title ?? session.id.prefix(8).description }
  }

  public struct LaneEntry: Sendable, Identifiable {
    public let lane: LaneID
    public let agentType: String?
    public let requests: Int
    public let fill: Double

    public static let mainTitle = "Main"

    public var id: String { lane.rawValue }
    public var title: String {
      lane == .main ? Self.mainTitle : (agentType ?? lane.rawValue.prefix(12).description)
    }
  }

  public private(set) var entries: [Entry] = []
  /// The one session ctxscope shows, by id. Nil until somebody picks one.
  public private(set) var focused: String?

  /// The focused session, when this machine still has it.
  public var wanted: SessionRef? {
    guard let focused else { return nil }
    return entries.first { $0.id == focused }?.session
  }

  /// The session written to most recently, for the one case where a `show`
  /// arrives without an id to focus.
  public var newest: SessionRef? {
    entries.first?.session
  }

  public init() {}

  public func focus(_ session: String?) {
    focused = session
  }

  /// Takes a new list, keeping whatever has already been measured about the
  /// sessions that are still in it.
  public func update(with sessions: [SessionRef]) {
    var known: [String: Entry] = [:]
    for entry in entries { known[entry.id] = entry }
    entries =
      sessions
      .sorted { left, right in
        if left.isLive != right.isLive { return left.isLive }
        return left.lastActivity > right.lastActivity
      }
      .map { session in
        var entry = known[session.id] ?? Entry(session: session)
        entry = Entry(session: session, fill: entry.fill, lanes: entry.lanes)
        return entry
      }
  }

  /// Takes the lanes of a session that has just been read.
  public func update(lanes recording: Recording, fill: Double?) {
    guard let slot = entries.firstIndex(where: { $0.id == recording.sessionID }) else { return }
    entries[slot].fill = fill ?? entries[slot].fill
    entries[slot].lanes = recording.lanes.map { lane in
      let peak = lane.snapshots.last?.usage.promptTotal ?? 0
      return LaneEntry(
        lane: lane.id,
        agentType: lane.agentType,
        requests: lane.snapshots.count,
        fill: lane.window.fill(peak)
      )
    }
  }

  public func lanes(of sessionID: String) -> [LaneEntry] {
    entries.first { $0.id == sessionID }?.lanes ?? []
  }
}
