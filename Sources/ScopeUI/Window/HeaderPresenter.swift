internal import Foundation
public import ScopeCore

public enum HeaderPresenter {
  public static func session(_ recording: Recording?) -> PopUpTitle {
    guard let recording else { return PopUpTitle("No session", emphasized: true) }
    return PopUpTitle(
      recording.title ?? String(recording.sessionID.prefix(8)),
      subtitle: folder(recording.project), emphasized: true)
  }

  public static func lane(_ shown: LaneID, in lanes: [SessionList.LaneEntry]) -> PopUpTitle {
    let name = lanes.first { $0.lane == shown }?.title ?? SessionList.LaneEntry.mainTitle
    let others = max(0, lanes.count - 1)
    return PopUpTitle(
      "Lane: \(name.lowercased())",
      subtitle: others > 0 ? "+ \(TokenFormat.plural(others, "subagent"))" : nil)
  }

  public static func item(_ entry: SessionList.Entry) -> String {
    let project = entry.session.project.split(separator: "/").last.map(String.init)
    return [entry.title, project].compactMap { $0 }.joined(separator: " · ")
  }

  public static func item(_ lane: SessionList.LaneEntry) -> String {
    "\(lane.title) · \(TokenFormat.plural(lane.requests, "request")) · "
      + TokenFormat.percent(lane.fill)
  }

  public static let liveTitle = "Live"

  static func folder(_ path: String) -> String {
    let home = NSHomeDirectory()
    guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
    return "~" + path.dropFirst(home.count)
  }
}
