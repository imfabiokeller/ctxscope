internal import Foundation
internal import ScopeCore

struct BreakWording {
  let title: String
  let detail: String

  init(bust: CacheBust, lane: Lane) {
    let after = Self.sentUncached(bust)
    switch bust.cause {
    case .memoryChanged:
      title = "Memory changed"
      detail = Self.moved(bust.change, fallback: "A memory file") + ", so " + after + "."
    case .systemChanged:
      title = "System prompt changed"
      detail = Self.moved(bust.change, fallback: "A system prompt section") + ", so " + after + "."
    case .toolsChanged:
      title = "Tool definitions changed"
      detail = Self.tools(bust.change) + " " + Self.capitalized(after) + "."
    case .idle:
      title = "Cache expired"
      detail =
        "\(Self.duration(bust.gapSeconds)) passed since request "
        + "\(RequestNumber.of(bust.parentRequest)), longer than the cache lasts. "
        + Self.capitalized(after) + "."
    case .compaction:
      title = "Context compacted"
      detail = "The conversation was summarized, so " + after + "."
    case .modelSwitch:
      title = "Model changed"
      detail = Self.models(bust, lane: lane) + " A model keeps its own cache, so " + after + "."
    case .rewind:
      title = "Continued from an earlier request"
      detail =
        "This request continued from request \(RequestNumber.of(bust.parentRequest)), "
        + "not the one before it, so " + after + "."
    case .unknown:
      title = "Cause not recorded"
      detail = "The transcript does not show what changed. " + Self.capitalized(after) + "."
    }
  }

  static func sentUncached(_ bust: CacheBust) -> String {
    switch bust.readThrough {
    case nil: "the whole context was sent uncached"
    case .system: "everything after the system prompt was sent uncached"
    case .tools: "everything after the system prompt and tools was sent uncached"
    case .memory: "everything after the system prompt, tools and memory was sent uncached"
    case .you, .agent, .results:
      "everything after the first \(TokenFormat.short(bust.actualReadTokens)) was sent uncached"
    }
  }

  static func moved(_ change: PrefixChange?, fallback: String) -> String {
    guard let change else { return fallback + " changed" }
    let verb =
      switch (change.added.isEmpty, change.removed.isEmpty) {
      case (false, false): "was edited"
      case (false, true): "was added"
      case (true, false): "was removed"
      case (true, true): "changed"
      }
    return "\(change.firstLabel) \(verb)"
  }

  static func tools(_ change: PrefixChange?) -> String {
    guard let change else { return "The tool definitions changed." }
    let added = change.added.count
    let removed = change.removed.count
    let server =
      change.servers.isEmpty
      ? nil
      : change.servers.joined(separator: ", ") + " MCP server"
        + (change.servers.count == 1 ? "" : "s")
    let addedPart = "\(TokenFormat.plural(added, "tool")) (\(UIFormat.tokens(change.addedTokens)))"
    let removedPart =
      "\(TokenFormat.plural(removed, "tool")) (\(UIFormat.tokens(change.removedTokens)))"
    switch (added > 0, removed > 0, server) {
    case (true, false, let server?): return "The \(server) connected and added \(addedPart)."
    case (false, true, let server?): return "The \(server) went away with \(removedPart)."
    case (true, true, _): return "\(capitalized(addedPart)) were added and \(removedPart) removed."
    case (true, false, nil): return "\(capitalized(addedPart)) were added."
    case (false, true, nil): return "\(capitalized(removedPart)) were removed."
    case (false, false, _): return "The tool definitions changed."
    }
  }

  static func models(_ bust: CacheBust, lane: Lane) -> String {
    let snapshots = lane.snapshots
    guard bust.parentRequest >= 0, bust.parentRequest < snapshots.count,
      bust.request < snapshots.count,
      snapshots[bust.parentRequest].model != snapshots[bust.request].model
    else { return "The model changed." }
    return
      "The model changed from \(snapshots[bust.parentRequest].model) "
      + "to \(snapshots[bust.request].model)."
  }

  static func duration(_ seconds: Double) -> String {
    let whole = max(0, Int(seconds.rounded()))
    if whole < 90 { return TokenFormat.plural(whole, "second") }
    if whole < 90 * 60 { return TokenFormat.plural(Int((seconds / 60).rounded()), "minute") }
    return TokenFormat.plural(Int((seconds / 3600).rounded()), "hour")
  }

  static func capitalized(_ text: String) -> String {
    text.prefix(1).uppercased() + text.dropFirst()
  }
}
