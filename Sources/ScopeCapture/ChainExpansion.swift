internal import Foundation

/// Parallel tool calls break the parent chain.
///
/// Claude Code writes one assistant entry per `tool_use` block, and each
/// result's `parentUuid` is its own `tool_use` entry. When a response makes
/// several calls at once, the chain continues through the last result only,
/// and every sibling result hangs off the chain. On this machine that is 73 of
/// 572 tool results in one session and 80 of 1078 in another: real prompt
/// content that a parent walk alone never sees.
///
/// This puts them back. A result belongs in the context exactly when its
/// `tool_use` entry does, so it is attached to that entry and leaves with it.
struct ChainExpansion {
  /// tool_use id to the uuid of the entry carrying its result.
  private var resultEntry: [String: String] = [:]
  /// entry uuid to the tool_use ids it issued.
  private var toolUses: [String: [String]] = [:]

  init() {}

  init(entries: [TranscriptEntry]) {
    for entry in entries { learn(from: entry) }
  }

  mutating func learn(from entry: TranscriptEntry) {
    switch entry.kind {
    case "assistant":
      guard let uuid = entry.uuid else { return }
      let ids = entry.blocks.compactMap { block -> String? in
        block["type"]?.string == "tool_use" ? block["id"]?.string : nil
      }
      if !ids.isEmpty { toolUses[uuid] = ids }
    case "user":
      guard let uuid = entry.uuid else { return }
      for block in entry.blocks where block["type"]?.string == "tool_result" {
        guard let id = block["tool_use_id"]?.string else { continue }
        resultEntry[id] = uuid
      }
    default:
      break
    }
  }

  struct Expansion {
    /// Entries entering the context, in prompt order.
    var added: [String]
    /// Results attached to an entry, so they leave when it does.
    var attached: [String: [String]]
    /// Tool calls that entered, and how many of them brought their result.
    var toolCalls: Int
    var toolCallsWithResult: Int
  }

  /// Expands what the parent walk added with the results that hang off it.
  /// `isMaterialized` answers whether an entry already has segments.
  func expand(
    added: [String],
    isMaterialized: (String) -> Bool
  ) -> Expansion {
    var order: [String] = []
    var attached: [String: [String]] = [:]
    var pending: [(owner: String, result: String)] = []
    var seen = Set(added)
    var calls = 0
    var withResult = 0

    func flush() {
      for item in pending {
        order.append(item.result)
        attached[item.owner, default: []].append(item.result)
      }
      pending.removeAll(keepingCapacity: true)
    }

    for uuid in added {
      guard let ids = toolUses[uuid] else {
        // A user or attachment entry ends the run of calls, and the results
        // of that run belong in front of it.
        flush()
        order.append(uuid)
        continue
      }
      order.append(uuid)
      for id in ids {
        calls += 1
        guard let result = resultEntry[id] else { continue }
        withResult += 1
        guard !seen.contains(result), !isMaterialized(result) else { continue }
        seen.insert(result)
        pending.append((uuid, result))
      }
    }
    flush()
    return Expansion(
      added: order,
      attached: attached,
      toolCalls: calls,
      toolCallsWithResult: withResult
    )
  }
}
