internal import Foundation
internal import ScopeCore

extension LaneBuilder {
  /// One API call: the entries that carry its streamed blocks, and the usage
  /// that must be counted once for all of them.
  struct RequestGroup {
    let key: String
    let entry: TranscriptEntry
    let usage: RequestUsage
    let entries: [TranscriptEntry]
    /// Worked out while the entries were still in hand, because a settled
    /// request no longer has them: whether the response finished, whether it
    /// produced thinking, and how many entries carried it.
    let finished: Bool
    let thinking: Bool
    let entryCount: Int
    /// The uuids of the entries that carried it, which is what the chain walk
    /// needs to say which request a later one continued from.
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

    /// The same request without its parsed entries. Everything later asked of
    /// it is already worked out.
    func settled() -> RequestGroup {
      RequestGroup(
        key: key, entry: entry, usage: usage, entries: [], finished: finished,
        thinking: thinking, entryCount: entryCount, uuids: uuids)
    }

    /// Whether this response produced any thinking, asked of the whole
    /// response rather than of one of its streamed entries.
    var hasThinking: Bool { thinking }

    /// Whether the response finished. Without a `stop_reason` anywhere in it,
    /// its `output_tokens` is a snapshot taken while the stream was still
    /// running: 8,516 of 70,554 subagent requests on this machine are in that
    /// state, and their totals run from one token to twenty.
    var isFinished: Bool { finished }
  }

  /// One finished call out of the entries that carry it.
  static func group(key: String, entries: [TranscriptEntry]) -> RequestGroup? {
    guard let first = entries.first, var usage = first.usage else { return nil }
    let group = entries
    // The prompt side is identical on every entry of a request, but the output
    // side is written as the stream advances: in subagent transcripts the first
    // entry can say one token and the last the real total. Take the largest,
    // which is the finished count.
    for entry in group.dropFirst() {
      guard let other = entry.usage else { continue }
      usage.outputTokens = max(usage.outputTokens, other.outputTokens)
      usage.thinkingTokens = max(usage.thinkingTokens, other.thinkingTokens)
    }
    // A request with no prompt at all is an error record, not a call.
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

  /// Which measured total each piece of an entry belongs to.
  ///
  /// The blocks the model produced are not estimated: re-sending them costs
  /// what the API charged for producing them. Thinking is its own group,
  /// because the transcript stores a summary of it and the real size is
  /// `thinking_tokens`.
  ///
  /// A response only counts as measured when it finished. Everything else is
  /// a number taken mid-stream, and believing one pins real blocks at the
  /// floor. The sizer's own test, that a total cannot cover the content it
  /// would have to, stays as the backstop for a response that says it finished
  /// and still reports something impossible.
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
    // The question is whether this response had thinking at all, which is a
    // property of the whole response. Asking it of the blocks of one entry
    // gets it wrong the moment a response is streamed as several entries: the
    // entry without the thinking block would set the output group back to the
    // full `output_tokens` and the thinking would be counted twice.
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

  /// Everything the model wrote at one request: what a later segment can be
  /// referenced by.
  static func consumerShingles(request: RequestGroup) -> [UInt64] {
    var text = ""
    // A tool definition has no words a response has to quote, so what makes it
    // referenced is the call itself. The call is carried as a
    // shingle of its own, so the index, the cutoff and the share all apply to
    // it unchanged.
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
    // No cap: consumers are model output, which is small, and capping them
    // biased the referenced share low for exactly the largest Write and Edit
    // calls.
    return Shingler.shingles(of: text) + calls
  }
}
