public import Foundation
public import ScopeCapture
public import ScopeCore

@MainActor
@Observable
public final class SessionList {
  public struct Entry: Sendable, Identifiable {
    public let session: SessionRef
    public var fill: Double?
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
  public private(set) var focused: String?

  public var wanted: SessionRef? {
    guard let focused else { return nil }
    return entries.first { $0.id == focused }?.session
  }

  public var newest: SessionRef? {
    entries.first?.session
  }

  public init() {}

  public func focus(_ session: String?) {
    focused = session
  }

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
