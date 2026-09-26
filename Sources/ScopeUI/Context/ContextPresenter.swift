public import ScopeCore

/// Which blocks the table lists.
public enum BlockFilter: String, Sendable, CaseIterable, Hashable {
  case all = "All"
  case unused = "Unused"
  case everyRequest = "Sent every request"
}

/// The Context page, worked out from a lane's analysis and the figures at
/// the playhead: every word and number it shows. A pure function, so what the
/// page says is tested without drawing it.
public enum ContextPresenter {
  /// What the page shows for a filter, a text filter on the names and a
  /// selection. `text` is the selected block's recorded text once it has
  /// been read, and `names` what each block is called once its detail has.
  public static func page(
    _ analysis: LaneAnalysis, _ figures: PlayheadFigures, filter: BlockFilter = .all,
    query: String = "", selection: SegmentID? = nil, text: String? = nil,
    names: BlockNames = BlockNames()
  ) -> ContextPageData {
    let table = BlockTable(analysis, figures, names: names)
    return ContextPageData(
      cards: cards(analysis, figures),
      strip: strip(
        analysis, figures, names: names, selected: selection.flatMap { table.span(of: $0) }),
      legend: legend(figures),
      blocks: blocks(
        count: figures.column.slices.count, rows: table.rows(filter: filter, query: query)),
      inspector: selection.flatMap {
        inspector(analysis, figures, table, block: $0, text: text, names: names)
      },
      noSelection: noSelection)
  }

  /// What the sidebar says while nothing is selected.
  public static let noSelection = "Select a block in the table or the strip."

  /// The Blocks section for a request of `count` blocks, with these rows.
  public static func blocks(count: Int, rows: [BlockRowData]) -> BlocksData {
    BlocksData(
      title: "Blocks", detail: "\(UIFormat.count(count)) in this request · largest first",
      columns: BlocksData.Columns(
        kind: "Kind", block: "Block", size: "Size ↓", carried: "Carried", used: "Used",
        cost: "Cost so far"),
      filterLabel: "Show", searchLabel: "Filter blocks", searchPrompt: "Filter", rows: rows)
  }

  /// The word a kind is written as, and the one for the untyped remainder.
  static func name(of kind: Kind?) -> String { kind?.rawValue ?? "untyped" }

  static func cards(_ analysis: LaneAnalysis, _ figures: PlayheadFigures) -> [SummaryCardData] {
    let request = figures.request
    let lane = analysis.lane
    let total = figures.tally?.total.value ?? 0
    let parent =
      lane.snapshots.indices.contains(request)
      ? (lane.snapshots[request].parentRequest ?? request - 1) : -1
    let before =
      lane.snapshots.indices.contains(parent)
      ? lane.snapshots[parent].usage.promptTotal : 0
    let added = total - before
    let cost = figures.cost
    let requests = lane.snapshots.isEmpty ? 0 : request + 1
    let prompts = analysis.prompts.prompts.count { $0.requests.lowerBound <= request }
    let breaks = analysis.cache.busts.count { $0.request <= request }
    let unused = figures.unused
    return [
      SummaryCardData(
        label: "Context", figure: TokenFormat.short(total),
        unit: "of \(TokenFormat.axis(lane.window.tokens))",
        detail: "\(TokenFormat.percent(figures.tally?.fill ?? 0)) full · "
          + "\(added < 0 ? "" : "+")\(TokenFormat.short(added)) this request"),
      SummaryCardData(
        label: "This request", figure: TokenFormat.dollars(cost?.context ?? 0),
        detail: "\(TokenFormat.short(cost?.readTokens ?? 0)) read from cache · "
          + "\(TokenFormat.short(cost?.writtenTokens ?? 0)) written"),
      SummaryCardData(
        label: "Session so far",
        figure: TokenFormat.dollars(analysis.costs.context(through: request)),
        detail: [
          TokenFormat.plural(requests, "request"), TokenFormat.plural(prompts, "prompt"),
          TokenFormat.plural(breaks, "cache break"),
        ].joined(separator: " · ")),
      SummaryCardData(
        label: "Carried, unused", figure: UIFormat.tokens(unused.tokens),
        detail: "\(TokenFormat.percent(unused.share)) of context · "
          + "\(TokenFormat.dollars(unused.dollars)) so far"),
    ]
  }

  static func strip(
    _ analysis: LaneAnalysis, _ figures: PlayheadFigures, names: BlockNames,
    selected: Range<Int>?
  ) -> StripData {
    let column = figures.column
    let scale = max(analysis.lane.window.tokens, column.end, column.cacheBoundary)
    let slices = column.slices.map { slice in
      StripSlice(
        id: slice.segment, start: slice.start, tokens: slice.tokens, grade: slice.grade,
        kind: slice.kind, label: analysis.segment(slice.segment).map(names.name(of:)) ?? "")
    }
    return StripData(
      title: "Context in reading order",
      scaleNote: "0 → \(TokenFormat.axis(scale)) tokens",
      scale: scale,
      slices: slices,
      prefix: column.prefixEnd > 0
        ? StripMark(
          at: column.prefixEnd,
          label: "sent with every request · \(TokenFormat.short(column.prefixEnd))") : nil,
      cache: column.cacheBoundary > 0
        ? StripMark(
          at: column.cacheBoundary,
          label: "cached up to here · \(TokenFormat.short(column.cacheBoundary))") : nil,
      selected: selected,
      request: MagnifierWords.request(figures.request),
      figures: MagnifierWords.figures(tokens: column.end, dollars: figures.cost?.context ?? 0))
  }

  /// Every kind with its size and share, then the untyped remainder when
  /// there is one.
  static func legend(_ figures: PlayheadFigures) -> [LegendEntryData] {
    guard let tally = figures.tally else { return [] }
    let total = max(1, tally.total.value)
    let kinds: [(Kind?, Tokens)] = zip(Kind.allCases, tally.byKind).map { ($0, $1) }
    let rest: [(Kind?, Tokens)] = tally.untyped.value > 0 ? [(nil, tally.untyped)] : []
    return (kinds + rest).map { kind, tokens in
      LegendEntryData(
        kind: kind, name: name(of: kind),
        detail: "\(UIFormat.tokens(tokens)) · "
          + TokenFormat.percent(Double(tokens.value) / Double(total)))
    }
  }
}
