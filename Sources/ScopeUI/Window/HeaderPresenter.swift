internal import Foundation
public import ScopeCore

/// What the window's header says about the session and the lane shown, and
/// how its menus list the others. Words only; the header lays them out.
public enum HeaderPresenter {
  /// The session's title, strong, with its project folder beside it.
  public static func session(_ recording: Recording?) -> PopUpTitle {
    guard let recording else { return PopUpTitle("No session", emphasized: true) }
    return PopUpTitle(
      recording.title ?? String(recording.sessionID.prefix(8)),
      subtitle: folder(recording.project), emphasized: true)
  }

  /// "Lane: main" with how many subagents there are besides it.
  public static func lane(_ shown: LaneID, in lanes: [SessionList.LaneEntry]) -> PopUpTitle {
    let name = lanes.first { $0.lane == shown }?.title ?? SessionList.LaneEntry.mainTitle
    let others = max(0, lanes.count - 1)
    return PopUpTitle(
      "Lane: \(name.lowercased())",
      subtitle: others > 0 ? "+ \(TokenFormat.plural(others, "subagent"))" : nil)
  }

  /// A session in the session menu: "retry-policy · api-client".
  public static func item(_ entry: SessionList.Entry) -> String {
    let project = entry.session.project.split(separator: "/").last.map(String.init)
    return [entry.title, project].compactMap { $0 }.joined(separator: " · ")
  }

  /// A lane in the lane menu: "explore · 12 requests · 40%".
  public static func item(_ lane: SessionList.LaneEntry) -> String {
    "\(lane.title) · \(TokenFormat.plural(lane.requests, "request")) · "
      + TokenFormat.percent(lane.fill)
  }

  public static let liveTitle = "Live"

  /// A project folder with the home folder written as "~".
  static func folder(_ path: String) -> String {
    let home = NSHomeDirectory()
    guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
    return "~" + path.dropFirst(home.count)
  }
}
