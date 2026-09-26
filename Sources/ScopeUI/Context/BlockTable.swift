internal import Foundation
internal import ScopeCore

/// The rows of the blocks table at one request: one per block, except tool
/// definitions, which are one row per server that offers them. Largest first.
struct BlockTable {
  /// A row with what the filters ask about, which the row itself does not
  /// carry.
  private struct Entry {
    let row: BlockRowData
    let tokens: Int
    /// Reading order position, which breaks ties between equal sizes.
    let position: Int
    let isPrefix: Bool
  }

  private let entries: [Entry]
  /// Where each block sits in the request, in tokens.
  private let spans: [SegmentID: Range<Int>]
  /// The row each block is listed under.
  private let rowOf: [SegmentID: Int]
  let groups: [SegmentID: ToolGroup]

  init(_ analysis: LaneAnalysis, _ figures: PlayheadFigures, names: BlockNames = BlockNames()) {
    var groups: [SegmentID: ToolGroup] = [:]
    for group in figures.toolGroups {
      for member in group.segments { groups[member] = group }
    }
    self.groups = groups
    var spans: [SegmentID: Range<Int>] = [:]
    var entries: [Entry] = []
    var rowOf: [SegmentID: Int] = [:]
    for (position, slice) in figures.column.slices.enumerated() {
      spans[slice.segment] = slice.start..<slice.end
      if let group = groups[slice.segment] {
        guard group.segments.first == slice.segment else { continue }
        for member in group.segments { rowOf[member] = entries.count }
        entries.append(Self.entry(group, position: position, analysis, figures))
      } else if let segment = analysis.segment(slice.segment) {
        rowOf[segment.id] = entries.count
        entries.append(Self.entry(segment, position: position, analysis, figures, names))
      }
    }
    self.spans = spans
    self.rowOf = rowOf
    self.entries = entries
  }

  /// The rows a filter and a text filter leave, largest first.
  func rows(filter: BlockFilter, query: String) -> [BlockRowData] {
    let query = query.trimmingCharacters(in: .whitespaces)
    return
      entries
      .filter { entry in
        switch filter {
        case .all: true
        case .unused: entry.row.use == .unused
        case .everyRequest: entry.isPrefix
        }
      }
      .filter { query.isEmpty || $0.row.label.localizedCaseInsensitiveContains(query) }
      .sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.position < $1.position }
      .map(\.row)
  }

  /// The tokens a selection covers in this request: its own, or its whole
  /// group's. Nil when it is not in the request.
  func span(of block: SegmentID) -> Range<Int>? {
    guard let row = rowOf[block] else { return nil }
    let members = entries[row].row.members.compactMap { spans[$0] }
    guard let low = members.map(\.lowerBound).min(), let high = members.map(\.upperBound).max()
    else { return nil }
    return low..<high
  }

  private static func entry(
    _ segment: Segment, position: Int, _ analysis: LaneAnalysis, _ figures: PlayheadFigures,
    _ names: BlockNames
  ) -> Entry {
    let use = UseAnalyzer.use(
      of: segment, finding: analysis.finding(of: segment.id), at: figures.request)
    let cost = figures.blockCosts.cost(of: segment.id)
    return Entry(
      row: BlockRowData(
        id: segment.id, members: [segment.id], kind: segment.kind,
        kindName: ContextPresenter.name(of: segment.kind), label: names.name(of: segment),
        size: UIFormat.tokens(segment.tokens),
        carried: "\(UIFormat.count(cost?.requestsIn ?? 0)) req",
        used: ContextPresenter.shortWord(use), use: use,
        cost: TokenFormat.cents(cost?.dollars ?? 0)),
      tokens: segment.tokens.value, position: position, isPrefix: segment.family == .prefix)
  }

  private static func entry(
    _ group: ToolGroup, position: Int, _ analysis: LaneAnalysis, _ figures: PlayheadFigures
  ) -> Entry {
    let costs = group.segments.compactMap { figures.blockCosts.cost(of: $0) }
    let grade = costs.map(\.grade).max() ?? group.tokens.grade
    let first = group.segments.first ?? SegmentID(0)
    return Entry(
      row: BlockRowData(
        id: first, members: group.segments, kind: .tools,
        kindName: ContextPresenter.name(of: .tools), label: ContextPresenter.title(of: group),
        size: UIFormat.tokens(Tokens(group.tokens.value, grade)),
        carried: "\(UIFormat.count(costs.map(\.requestsIn).max() ?? 0)) req",
        used: ContextPresenter.shortWord(.notTracked), use: .notTracked,
        cost: TokenFormat.cents(costs.reduce(0) { $0 + $1.dollars })),
      tokens: group.tokens.value, position: position, isPrefix: true)
  }
}
