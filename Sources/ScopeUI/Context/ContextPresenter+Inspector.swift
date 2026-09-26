internal import ScopeCore

/// The sidebar's account of a block, and the words a block's use and a tool
/// group are written with.
extension ContextPresenter {
  /// The Used column: yes, no, or not tracked.
  static func shortWord(_ use: BlockUse) -> String {
    switch use {
    case .used: "yes"
    case .unused: "no"
    case .notTracked: "not tracked"
    }
  }

  /// The sidebar's Used fact: the word, and what it means.
  static func longWord(_ use: BlockUse) -> (word: String, meaning: String) {
    switch use {
    case .used: ("Yes", "later text reuses it word for word")
    case .unused: ("No", "no later text reuses it")
    case .notTracked: ("Not tracked", "for this kind")
    }
  }

  /// "Built-in tools · 18 definitions", "github MCP · 26 tool definitions".
  static func title(of group: ToolGroup) -> String {
    switch group.server {
    case .builtIn: "Built-in tools · \(TokenFormat.plural(group.definitions, "definition"))"
    case .mcp(let id):
      "\(id.map { "\($0) MCP" } ?? "MCP") · "
        + TokenFormat.plural(group.definitions, "tool definition")
    }
  }

  static func inspector(
    _ analysis: LaneAnalysis, _ figures: PlayheadFigures, _ table: BlockTable,
    block: SegmentID, text: String?, names: BlockNames
  ) -> InspectorData? {
    guard let segment = analysis.segment(block) else { return nil }
    let group = table.groups[block]
    let members = group?.segments ?? [block]
    let costs = members.compactMap { figures.blockCosts.cost(of: $0) }
    let tokens = group?.tokens.value ?? segment.tokens.value
    let grade = costs.map(\.grade).max() ?? segment.tokens.grade
    let born = group?.born ?? segment.born
    let carried = costs.map(\.requestsIn).max() ?? 0
    let use =
      group == nil
      ? UseAnalyzer.use(of: segment, finding: analysis.finding(of: block), at: figures.request)
      : .notTracked
    let prompt = analysis.prompts.prompt(containing: born)
    let estimated = grade == .estimated
    let used = longWord(use)
    return InspectorData(
      block: block, kind: segment.kind, kindName: name(of: segment.kind),
      title: group.map(title(of:)) ?? names.name(of: segment),
      facts: [
        FactData(
          "Size", (estimated ? UIFormat.estimate : "") + UIFormat.count(tokens),
          detail: estimated ? "tokens, estimated" : "tokens"),
        FactData(
          "Carried", UIFormat.count(carried), detail: carried == 1 ? "request" : "requests"),
        FactData(
          "Cost so far", TokenFormat.cents(costs.reduce(0) { $0 + $1.dollars }),
          detail: "\(TokenFormat.dollars(costs.reduce(0) { $0 + $1.perRequest })) per request"),
        FactData(
          "Added in", "Request \(UIFormat.count(RequestNumber.of(born)))",
          detail: prompt.map { "prompt \($0.number)" }),
        FactData("Used", used.word, detail: used.meaning, wide: true),
        FactData("Came from", origin(of: segment, group: group, in: analysis), wide: true),
      ],
      textTitle: "Text", text: text, timelineTitle: "Show in timeline", copyTitle: "Copy text")
  }

  /// Who or what put a block into the context, in a few plain words.
  static func origin(of segment: Segment, group: ToolGroup?, in analysis: LaneAnalysis) -> String {
    if let group, case .mcp(let id) = group.server {
      let server = id.map { "MCP server \($0)" } ?? "An MCP server"
      return "\(server), connected in request \(UIFormat.count(RequestNumber.of(group.born)))"
    }
    switch segment.band {
    case .sys, .tools: return "Claude Code"
    case .mcp: return "An MCP server"
    case .mem: return "Memory file"
    case .unattr: return "Not recorded in the transcript"
    case .user:
      return analysis.lane.prompts.contains(segment.id) ? "Your prompt" : "Attached to a prompt"
    case .asst: return "Assistant turn, reply"
    case .think: return "Assistant turn, thinking"
    case .call: return "Assistant turn, tool call"
    case .read: return "Tool result, a file read"
    case .bash: return "Tool result, a command"
    case .srch: return "Tool result, a search"
    case .agent: return "Subagent result"
    }
  }
}
