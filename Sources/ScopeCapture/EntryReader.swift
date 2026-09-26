internal import Foundation
internal import ScopeCore

struct EntryReader {
  var toolNames: [String: String] = [:]
  var toolCalls: [String: String] = [:]
  var promptEntries: Set<String> = []
  private var prompts = TypedPrompts()

  mutating func learn(from entry: TranscriptEntry) {
    if prompts.isNewPrompt(entry), let uuid = entry.uuid { promptEntries.insert(uuid) }
    guard entry.kind == "assistant" else { return }
    for block in entry.blocks where block["type"]?.string == "tool_use" {
      guard let id = block["id"]?.string, let name = block["name"]?.string else { continue }
      toolNames[id] = name
      if let uuid = entry.uuid { toolCalls[id] = uuid }
    }
  }

  func pieces(of entry: TranscriptEntry) -> [ContentPiece] {
    switch entry.kind {
    case "assistant": assistantPieces(entry)
    case "user": userPieces(entry)
    case "attachment": attachmentPieces(entry)
    case "system": systemPieces(entry)
    default: []
    }
  }

  private func assistantPieces(_ entry: TranscriptEntry) -> [ContentPiece] {
    entry.blocks.compactMap { block in
      switch block["type"]?.string {
      case "text":
        let text = block["text"]?.string ?? ""
        return ContentPiece(
          band: .asst, label: "Assistant text", text: text,
          contentClass: ContentClassifier.classify(text), role: .output,
          subject: .firstLine(head: "Assistant text"))
      case "thinking":
        return ContentPiece(
          band: .think, label: "Thinking", text: block["thinking"]?.string ?? "",
          contentClass: .prose, role: .thinking, subject: .firstLine(head: "Thinking"))
      case "tool_use":
        let name = block["name"]?.string ?? "tool"
        let text = block["input"]?.compactText ?? ""
        return ContentPiece(
          band: .call, label: ClaudeCodeBands.label(tool: name, input: block["input"]),
          text: text, contentClass: .json, role: .output,
          subject: block["id"]?.string.map { .toolCall(id: $0, name: name) })
      default:
        return nil
      }
    }
  }

  private func userPieces(_ entry: TranscriptEntry) -> [ContentPiece] {
    if entry.isCompactSummary {
      let text = entry.blocks.map { $0["text"]?.string ?? "" }.joined()
      return [
        ContentPiece(
          band: .asst, label: "Compaction summary", text: text,
          contentClass: .prose, role: .input, subject: .firstLine(head: "Compaction summary"))
      ]
    }
    var pieces: [ContentPiece] = []
    var typed = entry.uuid.map(promptEntries.contains) ?? false
    for block in entry.blocks {
      switch block["type"]?.string {
      case "text":
        let text = block["text"]?.string ?? ""
        pieces.append(
          ContentPiece(
            band: .user, label: "User prompt", text: text,
            contentClass: ContentClassifier.classify(text), role: .input,
            isPrompt: typed, subject: .firstLine(head: "User prompt")))
        typed = false
      case "tool_result":
        let id = block["tool_use_id"]?.string
        let tool = id.flatMap { toolNames[$0] } ?? "tool"
        pieces.append(
          contentsOf: resultPieces(
            block["content"], tool: tool, subject: id.map { .toolResult(id: $0, name: tool) }))
      case "image", "document":
        pieces.append(imagePiece(block, band: .user))
      default:
        break
      }
    }
    return pieces
  }

  private func resultPieces(
    _ content: JSONValue?, tool: String, subject: BlockDetail.Subject?
  ) -> [ContentPiece] {
    let band = ClaudeCodeBands.band(forTool: tool)
    guard let content else { return [] }
    if let text = content.string {
      return [
        ContentPiece(
          band: band, label: "\(tool) result", text: text,
          contentClass: ContentClassifier.classify(text), role: .input,
          shingleText: band == .read ? Self.withoutLineNumbers(text) : nil, subject: subject)
      ]
    }
    guard let blocks = content.array else { return [] }
    return blocks.compactMap { block in
      switch block["type"]?.string {
      case "image", "document":
        return imagePiece(block, band: band)
      case "text", nil:
        let text = block["text"]?.string ?? ""
        guard !text.isEmpty else { return nil }
        return ContentPiece(
          band: band, label: "\(tool) result", text: text,
          contentClass: ContentClassifier.classify(text), role: .input,
          shingleText: band == .read ? Self.withoutLineNumbers(text) : nil, subject: subject)
      default:
        let text = block.compactText
        return ContentPiece(
          band: band, label: "\(tool) result", text: text,
          contentClass: .json, role: .input, subject: subject)
      }
    }
  }

  // The harness writes file reads as `   12\tcontent` or `   12->content`.
  static func withoutLineNumbers(_ text: String) -> String {
    var out = ""
    out.reserveCapacity(text.count)
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      var rest = Substring(line)
      while let first = rest.first, first == " " { rest = rest.dropFirst() }
      let digits = rest.prefix { $0.isNumber }
      if !digits.isEmpty, digits.count <= 7 {
        var after = rest.dropFirst(digits.count)
        if let next = after.first, next == "\t" || next == "\u{2192}" {
          after = after.dropFirst()
          rest = after
        } else if after.hasPrefix("->") {
          rest = after.dropFirst(2)
        } else if let next = after.first, next == " " {
          rest = after.drop { $0 == " " }
        }
      }
      out += rest
      out += "\n"
    }
    return out
  }

  private func imagePiece(_ block: JSONValue, band: Band) -> ContentPiece {
    // Base64 length says nothing about tokens, so images get their own class and rate.
    let data = block["source"]?["data"]?.string ?? ""
    return ContentPiece(
      band: band, label: "Image", text: data, contentClass: .image, role: .input)
  }

  private func systemPieces(_ entry: TranscriptEntry) -> [ContentPiece] {
    guard let text = entry.raw["content"]?.string, !text.isEmpty else { return [] }
    return [
      ContentPiece(
        band: .user, label: "System notice", text: text,
        contentClass: .prose, role: .input, subject: .firstLine(head: "System notice"))
    ]
  }
}
