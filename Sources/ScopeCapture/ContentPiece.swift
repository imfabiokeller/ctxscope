internal import Foundation
internal import ScopeCore

struct ContentPiece: Sendable {
  enum Role: Sendable {
    case thinking
    case output
    case input
  }

  let band: Band
  let label: String
  let text: String
  let contentClass: ContentClass
  let role: Role
  let isReliable: Bool
  // Without a file read's line numbers: they count toward size, but no edit can
  // quote them.
  let shingleText: String?
  // Unicode scalars, counted once: `String.count` walks graphemes on every call.
  let characters: Int
  let toolName: String?
  let isPrompt: Bool
  let subject: BlockDetail.Subject?

  init(
    band: Band,
    label: String,
    text: String,
    contentClass: ContentClass,
    role: Role,
    isReliable: Bool = true,
    shingleText: String? = nil,
    toolName: String? = nil,
    isPrompt: Bool = false,
    subject: BlockDetail.Subject? = nil
  ) {
    self.band = band
    self.label = label
    self.text = text
    self.contentClass = contentClass
    self.role = role
    self.isReliable = isReliable
    self.shingleText = shingleText
    self.toolName = toolName
    self.isPrompt = isPrompt
    self.subject = subject
    characters = text.unicodeScalars.count
  }

  static let framing = ContentPiece(
    band: .user, label: "Harness framing", text: "", contentClass: .prose, role: .input,
    isReliable: false)

  var textForJudge: String { shingleText ?? text }
}

enum ClaudeCodeBands {
  static func band(forTool name: String) -> Band {
    switch name {
    case "Read", "Edit", "Write", "MultiEdit", "NotebookEdit", "NotebookRead":
      .read
    case "Bash", "BashOutput", "KillShell", "KillBash":
      .bash
    case "Task", "Agent", "SendMessage", "TaskOutput":
      .agent
    default:
      .srch
    }
  }

  static func band(forAttachment type: String) -> Band {
    switch type {
    case "nested_memory", "instructions", "session_context", "output_style_instructions":
      .mem
    case "file", "already_read_file", "directory", "edited_text_file", "compact_file_reference":
      .read
    default:
      .user
    }
  }

  // Labels never carry the content of a block.
  static func label(tool: String, input: JSONValue?) -> String {
    guard let path = input?["file_path"]?.string ?? input?["notebook_path"]?.string else {
      return tool
    }
    let name = path.split(separator: "/").last.map(String.init) ?? path
    return "\(tool) \(name)"
  }
}
