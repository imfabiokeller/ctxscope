public import Foundation
public import ScopeCore

public enum UIFormat {
  public static let estimate = "~"

  public static func tokens(_ tokens: Tokens) -> String {
    mark(TokenFormat.short(tokens.value), tokens.grade)
  }

  public static func tokens(_ value: Int, _ grade: Grade) -> String {
    mark(TokenFormat.short(value), grade)
  }

  public static func percent(_ share: Double, _ grade: Grade) -> String {
    mark(TokenFormat.percent(share), grade)
  }

  // Fixed locale, so a figure reads the same on every machine.
  public static func count(_ value: Int) -> String {
    value.formatted(.number.locale(Locale(identifier: "en_US")))
  }

  private static func mark(_ text: String, _ grade: Grade) -> String {
    grade == .estimated ? estimate + text : text
  }
}

extension UIFormat {
  public static func ago(_ date: Date, now: Date, calendar: Calendar) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 60 { return "\(seconds) s ago" }
    if seconds < 3600 { return "\(seconds / 60) min ago" }
    let days =
      calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
      ).day ?? 0
    if days <= 0 { return "\(seconds / 3600) h ago" }
    if days == 1 { return "Yesterday" }
    return "\(days) days ago"
  }

  public static func folder(_ path: String, home: String) -> String {
    let home = home.hasSuffix("/") ? String(home.dropLast()) : home
    guard !home.isEmpty else { return path }
    if path == home { return "~" }
    return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
  }

  public static func cause(_ cause: CacheBustCause) -> String {
    switch cause {
    case .compaction: "the conversation was compacted"
    case .modelSwitch: "the model changed"
    case .rewind: "continued from an earlier request"
    case .systemChanged: "system prompt changed"
    case .toolsChanged: "tool definitions changed"
    case .memoryChanged: "memory files changed"
    case .idle: "the cache expired after a pause"
    case .unknown: "cause not known"
    }
  }
}
