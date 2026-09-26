public import ScopeCore

/// The Timeline page from a lane's analyses: a pure function from what
/// ScopeCore measured to what the page says. Every word on the page is
/// written here or in `BreakWording`, and nothing is measured here.
public enum TimelinePresenter {
  /// `promptLines` is the first line of each typed prompt, by its block, as
  /// `SessionHost.promptLines` reads it back. `selectedPrompt` is a prompt's
  /// number, from one; nil selects none and dims no column. `names` is what
  /// each block is called, as `SessionHost.blockDetails` reads it back.
  public static func present(
    lane: Lane,
    costs: CostAnalysis,
    cache: CacheAnalysis,
    prompts: PromptAnalysis,
    order: ReadingOrder,
    promptLines: [SegmentID: String],
    names: BlockNames = BlockNames(),
    selectedPrompt: Int?
  ) -> TimelineData {
    let selected = prompts.prompts.first { $0.number == selectedPrompt }
    let count = lane.requestCount
    let total = count > 0 ? costs.context(through: count - 1) : 0
    return TimelineData(
      headerNote: "\(TokenFormat.plural(count, "request")) · \(TokenFormat.dollars(total))",
      chart: TimelineChartPresenter.chart(
        lane: lane, costs: costs, cache: cache, order: order, names: names,
        highlighted: selected?.requests),
      prompts: prompts.prompts.map { row($0, lines: promptLines, selected: selected) },
      breaks: breaks(lane: lane, costs: costs, cache: cache, prompts: prompts),
      detail: selected.map {
        detail($0, lane: lane, costs: costs, cache: cache, lines: promptLines, names: names)
      }
    )
  }

  /// "1–5", request numbers as a person counts them.
  static func range(_ requests: ClosedRange<Int>) -> String {
    let first = RequestNumber.of(requests.lowerBound)
    let last = RequestNumber.of(requests.upperBound)
    return first == last ? "\(first)" : "\(first)\u{2013}\(last)"
  }

  /// "+4.5k", and "-2.1k" for a prompt a compaction made smaller.
  static func signed(_ tokens: Int) -> String {
    (tokens >= 0 ? "+" : "") + TokenFormat.short(tokens)
  }

  private static func line(of prompt: Prompt, _ lines: [SegmentID: String]) -> String {
    lines[prompt.segment] ?? "Prompt \(prompt.number)"
  }

  private static func row(
    _ prompt: Prompt, lines: [SegmentID: String], selected: Prompt?
  ) -> PromptRow {
    PromptRow(
      id: prompt.number,
      requests: prompt.requests,
      isSelected: prompt.number == selected?.number,
      number: TokenFormat.count(prompt.number),
      prompt: line(of: prompt, lines),
      range: range(prompt.requests),
      added: signed(prompt.addedTokens),
      cost: TokenFormat.dollars(prompt.cost),
      breaks: TokenFormat.count(prompt.cacheBreaks)
    )
  }

  private static func breaks(
    lane: Lane, costs: CostAnalysis, cache: CacheAnalysis, prompts: PromptAnalysis
  ) -> BreakList {
    let extra = cache.busts.reduce(0) { $0 + costs.extra(of: $1) }
    let cards = cache.busts.enumerated().map { index, bust in
      let wording = BreakWording(bust: bust, lane: lane)
      var place = "Request \(RequestNumber.of(bust.request))"
      if let prompt = prompts.prompt(containing: bust.request) {
        place += " · prompt \(prompt.number)"
      }
      return BreakCard(
        id: index + 1, place: place, extra: "+" + TokenFormat.dollars(costs.extra(of: bust)),
        title: wording.title, detail: wording.detail)
    }
    return BreakList(
      count: TokenFormat.count(cards.count), extra: "+" + TokenFormat.dollars(extra),
      suffix: "this session", cards: cards)
  }

  private static func detail(
    _ prompt: Prompt, lane: Lane, costs: CostAnalysis, cache: CacheAnalysis,
    lines: [SegmentID: String], names: BlockNames
  ) -> PromptDetail {
    let requests = prompt.requestCount
    let extra = cache.busts.filter { prompt.requests.contains($0.request) }
      .reduce(0) { $0 + costs.extra(of: $1) }
    var facts = [
      FactData(
        "Context", signed(prompt.addedTokens),
        detail:
          "\(TokenFormat.short(prompt.startTokens)) \u{2192} \(TokenFormat.short(prompt.endTokens))"
      ),
      FactData(
        "Cost", TokenFormat.dollars(prompt.cost),
        detail: TokenFormat.plural(requests, "request")),
      FactData("Per request", TokenFormat.dollars(prompt.cost / Double(requests))),
      FactData(
        "Cache breaks", TokenFormat.count(prompt.cacheBreaks),
        detail: prompt.cacheBreaks > 0 ? "+\(TokenFormat.dollars(extra)) sent again" : nil),
    ]
    if let id = prompt.largestAdded, let block = lane.segments.first(where: { $0.id == id }) {
      facts.append(
        FactData(
          "Largest addition", names.name(of: block), swatch: FactData.Swatch(block.kind),
          trailing: UIFormat.tokens(block.tokens), wide: true))
    }
    let last = prompt.requests.upperBound
    let noun = requests == 1 ? "request" : "requests"
    return PromptDetail(
      number: TokenFormat.count(prompt.number),
      requests: "\(noun) \(range(prompt.requests))",
      prompt: line(of: prompt, lines),
      facts: facts,
      link: "Show context at request \(RequestNumber.of(last))",
      linkRequest: last
    )
  }
}
