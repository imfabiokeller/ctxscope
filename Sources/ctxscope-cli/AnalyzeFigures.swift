import ScopeCore

// Privacy: no transcript text here, a task is named by its number.
struct WindowFigures: Encodable {
  struct Break: Encodable {
    let bust: CacheBust
    let extra: Double
  }

  let request: Int
  let kinds: [String: Tokens]
  let untyped: Tokens
  let prefixTokens: Tokens
  let cost: RequestCost
  let sessionContextCost: Double
  let sessionTotalCost: Double
  let unused: UnusedSummary
  let breaks: [Break]
  let prompts: [Prompt]
  let promptAtRequest: Int?
  let toolGroups: [ToolGroup]

  init(
    lane: Lane, at request: Int, references: ReferenceReport, tally: Tally,
    cache: CacheAnalysis, segmentCache: SegmentCacheAnalysis
  ) {
    let costs = CostAnalyzer.run(lane)
    let findings = references.bySegment()
    let blocks = BlockCostAnalyzer.run(
      lane, cache: segmentCache, costs: costs, upTo: request)
    let entry = tally.perRequest[request]
    let prompts = PromptAnalyzer.run(lane, costs: costs, cache: cache)
    self.request = request
    kinds = Dictionary(
      uniqueKeysWithValues: Kind.allCases.map { ($0.rawValue, entry.tokens(of: $0)) })
    untyped = entry.untyped
    prefixTokens = entry.prefixTokens
    cost = costs.perRequest[request]
    sessionContextCost = costs.context(through: request)
    sessionTotalCost = costs.total(through: request)
    unused = UseAnalyzer.unused(lane, findings: findings, costs: blocks, at: request)
    breaks = cache.busts.map { Break(bust: $0, extra: costs.extra(of: $0)) }
    self.prompts = prompts.prompts
    promptAtRequest = prompts.prompt(containing: request)?.number
    toolGroups = ToolGroupAnalyzer.run(lane, findings: findings, at: request)
  }

  var lines: [String] {
    var lines: [String] = []
    lines.append(
      "kinds        "
        + Kind.allCases.map {
          "\($0.rawValue) \(TokenFormat.tokens(kinds[$0.rawValue]?.value ?? 0))"
        }
        .joined(separator: "  ")
        + (untyped.value > 0 ? "  untyped \(TokenFormat.tokens(untyped.value))" : ""))
    lines.append(
      "this request \(TokenFormat.dollars(cost.context)): "
        + "\(TokenFormat.tokens(cost.readTokens)) read, "
        + "\(TokenFormat.tokens(cost.writtenTokens)) written, "
        + "\(TokenFormat.tokens(cost.uncachedTokens)) uncached"
        + "   output \(TokenFormat.dollars(cost.output))")
    lines.append(
      "each request \(TokenFormat.dollars(cost.readAgain)) from the cache, "
        + "\(TokenFormat.dollars(cost.sentAgain)) if sent again"
        + "   sent with every request \(TokenFormat.tokens(prefixTokens.value))")
    lines.append(
      "session      \(TokenFormat.dollars(sessionContextCost)) context, "
        + "\(TokenFormat.dollars(sessionTotalCost)) with output")
    lines.append(
      "unused       \(TokenFormat.tokens(unused.tokens.value)), "
        + "\(TokenFormat.percent(unused.share)) of context, "
        + "\(TokenFormat.dollars(unused.dollars)) so far, "
        + TokenFormat.plural(unused.blocks, "block"))
    let breaksSoFar = breaks.filter { $0.bust.request <= request }
    lines.append(
      "tasks        \(TokenFormat.plural(prompts.count, "prompt")), "
        + (promptAtRequest.map { "this request is in prompt \($0)" } ?? "this request is in none")
        + "   \(TokenFormat.plural(breaksSoFar.count, "cache break")) so far, "
        + TokenFormat.dollars(breaksSoFar.reduce(0) { $0 + $1.extra }) + " extra")
    for group in toolGroups {
      lines.append(
        "  tools " + TokenFormat.padRight(Self.name(group.server), to: 24)
          + TokenFormat.pad("\(group.definitions)", to: 4) + " definitions"
          + TokenFormat.pad(TokenFormat.tokens(group.tokens.value), to: 9)
          + "   called \(group.called) of \(group.named)")
    }
    return lines
  }

  private static func name(_ server: ToolServer) -> String {
    switch server {
    case .builtIn: "built-in"
    case .mcp(let id?): "mcp " + id
    case .mcp(nil): "mcp, unnamed"
    }
  }
}
