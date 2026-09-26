internal import Foundation

// Transcript text: hand it to the window only, never record, log or report it.
public struct BlockDetail: Sendable, Hashable {
  public let head: String
  public let detail: String

  public init(head: String, detail: String) {
    self.head = head
    self.detail = detail
  }

  public static let limit = 60

  enum Subject: Sendable, Hashable {
    case toolCall(id: String, name: String)
    case toolResult(id: String, name: String)
    case firstLine(head: String)
    case attachment(type: String)
    case memory(path: String)
  }

  static func line(_ head: String, text: String) -> BlockDetail? {
    PromptLine.first(of: text, limit: limit).map { BlockDetail(head: head, detail: $0) }
  }

  static func attachment(type: String, record: JSONValue?, project: String?) -> BlockDetail {
    if let file = record?["filename"]?.string ?? record?["path"]?.string {
      return BlockDetail(head: "Attachment", detail: path(file, project: project))
    }
    let name = type.replacingOccurrences(of: "_", with: " ")
    return BlockDetail(head: "Attachment", detail: cut(name))
  }

  static func memory(path file: String, project: String?) -> BlockDetail {
    BlockDetail(head: "Memory", detail: path(file, project: project))
  }

  static func path(
    _ path: String, project: String?, home: String = NSHomeDirectory()
  ) -> String {
    if let project, let inside = relative(path, to: project) {
      return middle(inside, limit: limit)
    }
    if let inside = relative(path, to: home) { return middle("~/" + inside, limit: limit) }
    return middle(path, limit: limit)
  }

  private static func relative(_ path: String, to folder: String) -> String? {
    guard !folder.isEmpty else { return nil }
    let base = folder.hasSuffix("/") ? folder : folder + "/"
    return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : nil
  }

  static func middle(_ text: String, limit: Int) -> String {
    guard text.count > limit, limit > 2 else { return text }
    let name = text.split(separator: "/").last.map(\.count) ?? 0
    let tail = min(limit - 2, max(limit / 2, name))
    return text.prefix(limit - 1 - tail) + "\u{2026}" + text.suffix(tail)
  }

  static func cut(_ text: String) -> String {
    PromptLine.first(of: text, limit: limit, markup: false) ?? text
  }
}
