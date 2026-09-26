internal import Foundation
internal import ScopeCore

/// One content block of one entry, mapped onto a band. This is where
/// harness-specific shapes stop: everything past this point is domain.
struct ContentPiece: Sendable {
  enum Role: Sendable {
    /// A thinking block. Its size is `thinking_tokens` of the request that
    /// produced it, not the length of the summary the transcript stores.
    case thinking
    /// Text or a tool call the model produced. Sized from `output_tokens`.
    case output
    /// Everything the harness or the user put in. Estimated.
    case input
  }

  let band: Band
  let label: String
  let text: String
  let contentClass: ContentClass
  let role: Role
  /// False when the text is reconstructed from an attachment whose rendering
  /// the harness did not record, so its length is a hint rather than a fact.
  let isReliable: Bool
  /// The text the judge should shingle, when that is not the text itself.
  /// A file read carries line numbers that are in the prompt and so count
  /// towards its size, but that no later edit can ever quote, so leaving them
  /// in makes most five word shingles of short code lines unmatchable.
  let shingleText: String?
  /// Counted once, in unicode scalars. `String.count` walks graphemes on
  /// every call, and this is read for every block of every request.
  let characters: Int
  /// The tool this piece is the definition of, when it is one. Such a piece is
  /// judged by whether the tool was called rather than by its words.
  let toolName: String?
  /// True for the text of a prompt the person typed, the block a task starts
  /// at. At most one piece of an entry is one.
  let isPrompt: Bool
  /// What the piece is about, which says where its detail is read from. Nil
  /// for a piece that has no detail to show, such as an image.
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

  /// The stand-in for what the harness injected and did not record. It has no
  /// text, so the judge never sees it and the calibration never learns from
  /// it.
  static let framing = ContentPiece(
    band: .user, label: "Harness framing", text: "", contentClass: .prose, role: .input,
    isReliable: false)

  /// What the judge sees. Never shorter on purpose than what it stands for.
  var textForJudge: String { shingleText ?? text }
}

/// Maps Claude Code content onto bands. The band list itself lives in
/// `BandRegistry`, this only decides which case a piece of harness output
/// belongs to.
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
      // Grep, Glob, WebSearch, WebFetch, ToolSearch, Skill and every MCP tool
      // return searched or fetched material.
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
      // Reminders, listings, environment, queued commands: things the harness
      // adds to the user turn.
      .user
    }
  }

  /// A short, neutral name. Never the content of a block.
  static func label(tool: String, input: JSONValue?) -> String {
    guard let path = input?["file_path"]?.string ?? input?["notebook_path"]?.string else {
      return tool
    }
    let name = path.split(separator: "/").last.map(String.init) ?? path
    return "\(tool) \(name)"
  }
}
