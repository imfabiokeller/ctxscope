internal import Foundation
internal import ScopeCore

extension EntryReader {
  static let snapshotType = "prompt_snapshot"

  func attachmentPieces(_ entry: TranscriptEntry) -> [ContentPiece] {
    guard let type = entry.attachmentType else { return [] }
    // A snapshot is the prefix, not a turn: its blocks are made where the prefix is
    // made, whatever request the snapshot turns up at.
    if type == Self.snapshotType { return [] }
    if let files = Self.memoryPieces(entry) { return files }
    if let tools = Self.loadedToolPieces(entry) { return tools }
    let band = ClaudeCodeBands.band(forAttachment: type)
    let label = "Attachment: \(type)"
    let rendered = Self.renderedText(entry.renderedBlocks)
    if !rendered.isEmpty {
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

  // Measured: loading these does not bust the cache, so they are content of the
  // turn they arrive in, not a changed prefix.
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

  private static func memoryLabel(_ file: JSONValue) -> String {
    let path = file["displayPath"]?.string ?? file["path"]?.string ?? "memory"
    return "Memory " + (path.split(separator: "/").last.map(String.init) ?? path)
  }

  // Rendered blocks are `{"content": ...}` in current transcripts; `text` is read too.
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

  static func snapshotTools(_ attachment: JSONValue) -> [ContextReport.Tool] {
    (attachment["tools"]?.array ?? []).enumerated().compactMap { index, tool in
      guard let name = tool["name"]?.string else { return nil }
      return ContextReport.Tool(
        name: name,
        server: tool["server"]?.string,
        tokens: nil,
        // The compact schema is what the API was given; its length tracks the harness's
        // own per-tool counts far better than the pretty printed wrapper.
        characters: toolSchema(attachment, at: index)?.jsonText(pretty: false)
          .unicodeScalars.count ?? 0,
        index: index
      )
    }
  }

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
