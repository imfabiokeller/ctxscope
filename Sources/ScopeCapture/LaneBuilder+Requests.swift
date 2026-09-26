internal import Foundation
internal import ScopeCore

extension LaneBuilder {
  struct RequestGroup {
    let key: String
    let entry: TranscriptEntry
    let usage: RequestUsage
    let entries: [TranscriptEntry]
    let finished: Bool
    let thinking: Bool
    let entryCount: Int
    let uuids: [String]

    init(
      key: String,
      entry: TranscriptEntry,
      usage: RequestUsage,
      entries: [TranscriptEntry],
      finished: Bool,
      thinking: Bool,
      entryCount: Int,
      uuids: [String]
    ) {
      self.key = key
      self.entry = entry
      self.usage = usage
      self.entries = entries
      self.finished = finished
      self.thinking = thinking
      self.entryCount = entryCount
      self.uuids = uuids
    }

    func settled() -> RequestGroup {
      RequestGroup(
        key: key, entry: entry, usage: usage, entries: [], finished: finished,
        thinking: thinking, entryCount: entryCount, uuids: uuids)
    }

    var hasThinking: Bool { thinking }

    // Without a `stop_reason`, `output_tokens` is a mid-stream snapshot, not the total.
    var isFinished: Bool { finished }
  }

  static func group(key: String, entries: [TranscriptEntry]) -> RequestGroup? {
    guard let first = entries.first, var usage = first.usage else { return nil }
    let group = entries
    // Output usage grows across a request's streamed entries; the largest is final.
    for entry in group.dropFirst() {
      guard let other = entry.usage else { continue }
      usage.outputTokens = max(usage.outputTokens, other.outputTokens)
      usage.thinkingTokens = max(usage.thinkingTokens, other.thinkingTokens)
    }
    // A request with no prompt is an error record, not a call.
    guard usage.promptTotal > 0 else { return nil }
    return RequestGroup(
      key: key,
      entry: first,
      usage: usage,
      entries: group,
      finished: group.contains { $0.stopReason != nil },
      thinking: group.contains { entry in
        entry.blocks.contains { $0["type"]?.string == "thinking" }
      },
      entryCount: group.count,
      uuids: group.compactMap(\.uuid)
    )
  }

  // The transcript stores a summary of thinking; its real size is `thinking_tokens`.
  static func groups(
    for entry: TranscriptEntry,
    pieces: [ContentPiece],
    origin: RequestGroup?,
    originIndex: Int?,
    complete: Bool,
    totals: inout [Int: Int]
  ) -> [Int?] {
    guard entry.kind == "assistant", complete, let origin, let originIndex,
      origin.isFinished
    else {
      return pieces.map { _ in nil }
    }
    let thinkingGroup = originIndex * 2
    let outputGroup = originIndex * 2 + 1
    let thinking = origin.usage.thinkingTokens
    // Asked of the whole response: asked per entry, a response streamed as several
    // entries would count its thinking twice.
    let hasThinkingTotal = thinking > 0 && origin.hasThinking
    if hasThinkingTotal {
      totals[thinkingGroup] = thinking
      totals[outputGroup] = origin.usage.visibleOutputTokens
    } else {
      totals[outputGroup] = origin.usage.outputTokens
    }
    return pieces.map { piece in
      switch piece.role {
      case .thinking: hasThinkingTotal ? thinkingGroup : outputGroup
      case .output: outputGroup
      case .input: nil
      }
    }
  }

  static func consumerShingles(request: RequestGroup) -> [UInt64] {
    var text = ""
    var calls: [UInt64] = []
    for entry in request.entries {
      for block in entry.blocks {
        switch block["type"]?.string {
        case "text": text += (block["text"]?.string ?? "") + "\n"
        case "thinking": text += (block["thinking"]?.string ?? "") + "\n"
        case "tool_use":
          text += (block["input"]?.compactText ?? "") + "\n"
          if let name = block["name"]?.string { calls.append(Shingler.toolCall(name)) }
        default: break
        }
      }
    }
    // Not capped: model output is small, and a cap biased the reused share low for
    // the largest Write and Edit calls.
    return Shingler.shingles(of: text) + calls
  }
}
