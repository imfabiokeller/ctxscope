internal import Foundation

/// What a block is about, in a few words: the tool and its key input, or the
/// start of what was written. "Read" and "src/api/client.ts", "Bash" and
/// "npm test".
///
/// It is transcript text, like `PromptLine`. It is worked out from an entry
/// read back out of the file when asked for, handed to the window only, and
/// never recorded, logged or reported. A segment's label stays the short
/// neutral name it always was.
public struct BlockDetail: Sendable, Hashable {
  /// What the block is: a tool's name, "Thinking", "User prompt".
  public let head: String
  /// What it is about, shortened.
  public let detail: String

  public init(head: String, detail: String) {
    self.head = head
    self.detail = detail
  }

  /// Characters a detail is cut to, ellipsis included.
  public static let limit = 60

  /// What a piece of an entry is, which says where its detail comes from.
  enum Subject: Sendable, Hashable {
    /// A tool call, or what it returned: the call's input says what it did.
    case toolCall(id: String, name: String)
    case toolResult(id: String, name: String)
    /// Written text, told by its first line: `head` is what it is.
    case firstLine(head: String)
    /// Something the harness attached, of this type.
    case attachment(type: String)
    /// A memory file, at this path.
    case memory(path: String)
  }

  /// The detail of a text told by its first line. Nil for a blank text.
  static func line(_ head: String, text: String) -> BlockDetail? {
    PromptLine.first(of: text, limit: limit).map { BlockDetail(head: head, detail: $0) }
  }

  /// An attachment by its file when it names one, else by its type.
  static func attachment(type: String, record: JSONValue?, project: String?) -> BlockDetail {
    if let file = record?["filename"]?.string ?? record?["path"]?.string {
      return BlockDetail(head: "Attachment", detail: path(file, project: project))
    }
    let name = type.replacingOccurrences(of: "_", with: " ")
    return BlockDetail(head: "Attachment", detail: cut(name))
  }

  /// A memory file by its path in the project.
  static func memory(path file: String, project: String?) -> BlockDetail {
    BlockDetail(head: "Memory", detail: path(file, project: project))
  }

  /// A path relative to the project when it is inside it, from "~" when it
  /// is in the home folder, cut in the middle so the file's own name stays
  /// whole where it can.
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

  /// Cut in the middle to `limit` characters, keeping the end, which is
  /// where a path's file name is.
  static func middle(_ text: String, limit: Int) -> String {
    guard text.count > limit, limit > 2 else { return text }
    let name = text.split(separator: "/").last.map(\.count) ?? 0
    let tail = min(limit - 2, max(limit / 2, name))
    return text.prefix(limit - 1 - tail) + "\u{2026}" + text.suffix(tail)
  }

  /// The first line of a text, shortened, or the text as it is when no line
  /// has anything on it.
  static func cut(_ text: String) -> String {
    PromptLine.first(of: text, limit: limit, markup: false) ?? text
  }
}
