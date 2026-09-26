internal import Foundation
internal import ScopeCore

/// What an attachment contributes to a prompt.
///
/// Attachments are where the harness puts everything it injects around a turn:
/// the environment, the memory files, the skill listing, the tool deltas, and
/// the one record that carries the real system prompt.
extension EntryReader {
  static let snapshotType = "prompt_snapshot"

  func attachmentPieces(_ entry: TranscriptEntry) -> [ContentPiece] {
    guard let type = entry.attachmentType else { return [] }
    // A snapshot is the prefix, not a turn. Its blocks are born at the first
    // request whatever request the snapshot itself turns up at, so they are
    // made where the prefix is made and never here.
    if type == Self.snapshotType { return [] }
    if let files = Self.memoryPieces(entry) { return files }
    if let tools = Self.loadedToolPieces(entry) { return tools }
    let band = ClaudeCodeBands.band(forAttachment: type)
    let label = "Attachment: \(type)"
    let rendered = Self.renderedText(entry.renderedBlocks)
    if !rendered.isEmpty {
      // What the harness says it injected, which is the exact text.
      return [
        ContentPiece(
          band: band, label: label, text: rendered,
          contentClass: ContentClassifier.classify(rendered), role: .input,
          subject: .attachment(type: type))
      ]
    }
    guard let attachment = entry.attachment?.object else { return [] }
    var text = ""
    for key in ["text", "content", "snippet", "banner", "prompt"] {
      if let value = attachment[key]?.string { text += value }
    }
    guard !text.isEmpty else { return [] }
    return [
      ContentPiece(
        band: band, label: label, text: text,
        contentClass: ContentClassifier.classify(text), role: .input,
        isReliable: false, subject: .attachment(type: type))
    ]
  }

  /// One block per tool a search loaded into the context part way through.
  ///
  /// `deferred_tools_record` carries the full definition of every tool
  /// `ToolSearch` brought in, and it sits in the turn that loaded them.
  /// Measured on four real sessions: the request after one of these reads back
  /// exactly what the request before it read plus what it wrote, so the cache
  /// is not busted and the definitions are appended content, not a prefix that
  /// changed. They are therefore blocks of the request they arrive at, sized
  /// by the estimator like anything else that entered there.
  static func loadedToolPieces(_ entry: TranscriptEntry) -> [ContentPiece]? {
    guard entry.attachmentType == "deferred_tools_record",
      let entries = entry.attachment?["entries"]?.array, !entries.isEmpty
    else { return nil }
    let pieces = entries.compactMap { record -> ContentPiece? in
      guard let name = record["name"]?.string else { return nil }
      let tool = ContextReport.Tool(
        name: name, server: record["server"]?.string, tokens: nil, characters: 0)
      let text = record.jsonText()
      return ContentPiece(
        band: tool.isMCP ? .mcp : .tools,
        label: tool.label,
        text: text,
        contentClass: .json,
        role: .input,
        toolName: name
      )
    }
    return pieces.isEmpty ? nil : pieces
  }

  /// One block per memory file, rather than one block for the whole
  /// injection.
  ///
  /// `instructions` carries `files[]` of `{path, content, type}` and
  /// `nested_memory` one object of the same shape, so which file costs what is
  /// recorded and never has to be guessed at. What is left out is the sentence
  /// the harness wraps each file in, about a hundred characters a file, which
  /// falls into the derived remainder with the rest of the framing.
  static func memoryPieces(_ entry: TranscriptEntry) -> [ContentPiece]? {
    guard let attachment = entry.attachment else { return nil }
    let files: [JSONValue]
    switch entry.attachmentType {
    case "instructions": files = attachment["files"]?.array ?? []
    case "nested_memory": files = attachment["content"].map { [$0] } ?? []
    default: return nil
    }
    let pieces = files.compactMap { file -> ContentPiece? in
      guard let text = file["content"]?.string, !text.isEmpty else { return nil }
      return ContentPiece(
        band: .mem, label: memoryLabel(file), text: text,
        contentClass: ContentClassifier.classify(text), role: .input,
        subject: (file["path"]?.string ?? file["displayPath"]?.string).map { .memory(path: $0) })
    }
    return pieces.isEmpty ? nil : pieces
  }

  /// A short, neutral name: the file's own, the way a file read is named.
  private static func memoryLabel(_ file: JSONValue) -> String {
    let path = file["displayPath"]?.string ?? file["path"]?.string ?? "memory"
    return "Memory " + (path.split(separator: "/").last.map(String.init) ?? path)
  }

  /// The text of a `rendered` array, which is what the harness says it
  /// injected for an attachment.
  ///
  /// Every rendered block on this machine is `{"content": "..."}`, with no
  /// `type` and no `text`. Reading only `text` therefore found an empty string
  /// and dropped the attachment, and `environment`, `instructions`,
  /// `session_context`, `model`, `date` and `output_style_instructions` carry
  /// a rendering and nothing else: all of them counted as zero. Both keys are
  /// read, so a transcript written in either shape is sized.
  static func renderedText(_ blocks: [JSONValue]?) -> String {
    guard let blocks else { return "" }
    return
      blocks
      .compactMap { $0["content"]?.string ?? $0["text"]?.string }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  static func systemBlocks(_ attachment: JSONValue) -> [String] {
    (attachment["systemPrompt"]?.array ?? []).compactMap { $0.string }.filter { !$0.isEmpty }
  }

  /// The tool list a snapshot wrote down, as records the prefix split can use.
  ///
  /// Only the tools of the request are in it. A tool the harness defers is not
  /// in the context and is not written here, so it never becomes a block.
  static func snapshotTools(_ attachment: JSONValue) -> [ContextReport.Tool] {
    (attachment["tools"]?.array ?? []).enumerated().compactMap { index, tool in
      guard let name = tool["name"]?.string else { return nil }
      return ContextReport.Tool(
        name: name,
        server: tool["server"]?.string,
        tokens: nil,
        // The schema is the record the API was given, so its compact length
        // is what the estimator sizes the tool from and what a share of a
        // reported band total is divided by. Measured against the harness's
        // own 30 per tool numbers it comes to 2.83 characters per token with a
        // coefficient of variation of 0.03; the pretty printed wrapper this
        // used to measure came to 4.84 with 0.15, because it counts the
        // description twice and the indentation once. It is rendered here and
        // thrown away: only the length is kept.
        characters: toolSchema(attachment, at: index)?.jsonText(pretty: false)
          .unicodeScalars.count ?? 0,
        index: index
      )
    }
  }

  /// One tool's definition, re-rendered as the JSON it is.
  ///
  /// This is a block's text, so it is produced from an entry the reader has
  /// just read back out of the transcript rather than from anything held in
  /// memory between requests. It is the `schema`, which is the record the API
  /// was given (`name`, `description`, `input_schema`), not the wrapper the
  /// snapshot puts around it: the wrapper repeats the description beside the
  /// schema that already holds it.
  static func toolDefinition(_ attachment: JSONValue, at index: Int) -> String? {
    toolSchema(attachment, at: index)?.jsonText()
  }

  static func toolSchema(_ attachment: JSONValue, at index: Int) -> JSONValue? {
    guard let tools = attachment["tools"]?.array, index >= 0, index < tools.count else {
      return nil
    }
    return tools[index]["schema"] ?? tools[index]
  }

}
