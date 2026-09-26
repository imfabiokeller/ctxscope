internal import Foundation

// Claude Code writes one entry per `tool_use`, so with parallel calls only the
// last result is on the parent chain. Siblings are attached to their call here.
struct ChainExpansion {
  private var resultEntry: [String: String] = [:]
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
    var added: [String]
    var attached: [String: [String]]
    var toolCalls: Int
    var toolCallsWithResult: Int
  }

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
        // A user or attachment entry ends a run of calls; the run's results go in front of it.
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
