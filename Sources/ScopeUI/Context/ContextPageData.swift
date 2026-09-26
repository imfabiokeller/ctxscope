public import ScopeCore

/// Everything the Context page shows, as plain values: every word and every
/// figure already written out. The views lay these out and decide nothing.
///
/// Built by `ContextPresenter` from a lane's analysis at the playhead, and by
/// the snapshot tool straight from sample values.
public struct ContextPageData: Sendable {
  public var cards: [SummaryCardData]
  public var strip: StripData
  public var legend: [LegendEntryData]
  public var blocks: BlocksData
  /// Nil while nothing is selected.
  public var inspector: InspectorData?
  /// What the sidebar says while nothing is selected.
  public var noSelection: String

  public init(
    cards: [SummaryCardData], strip: StripData, legend: [LegendEntryData], blocks: BlocksData,
    inspector: InspectorData?, noSelection: String
  ) {
    self.cards = cards
    self.strip = strip
    self.legend = legend
    self.blocks = blocks
    self.inspector = inspector
    self.noSelection = noSelection
  }
}

/// One of the four summary cards.
public struct SummaryCardData: Sendable, Hashable, Identifiable {
  public let label: String
  public let figure: String
  public let unit: String?
  public let detail: String
  public var id: String { label }

  public init(label: String, figure: String, unit: String? = nil, detail: String) {
    self.label = label
    self.figure = figure
    self.unit = unit
    self.detail = detail
  }
}

/// A kind in the legend under the strip. A nil kind is the untyped remainder.
public struct LegendEntryData: Sendable, Hashable, Identifiable {
  public let kind: Kind?
  public let name: String
  public let detail: String
  public var id: String { name }

  public init(kind: Kind?, name: String, detail: String) {
    self.kind = kind
    self.name = name
    self.detail = detail
  }
}

/// The Blocks section: its line, the words of its controls and columns, and
/// the rows the filters leave.
public struct BlocksData: Sendable {
  /// The table's column titles, in the order the columns stand.
  public struct Columns: Sendable, Hashable {
    public let kind: String
    public let block: String
    public let size: String
    public let carried: String
    public let used: String
    public let cost: String

    public init(
      kind: String, block: String, size: String, carried: String, used: String, cost: String
    ) {
      self.kind = kind
      self.block = block
      self.size = size
      self.carried = carried
      self.used = used
      self.cost = cost
    }
  }

  public let title: String
  public let detail: String
  public let columns: Columns
  /// What accessibility calls the filter picker and the text field, and what
  /// the empty field shows.
  public let filterLabel: String
  public let searchLabel: String
  public let searchPrompt: String
  public let rows: [BlockRowData]

  public init(
    title: String, detail: String, columns: Columns, filterLabel: String, searchLabel: String,
    searchPrompt: String, rows: [BlockRowData]
  ) {
    self.title = title
    self.detail = detail
    self.columns = columns
    self.filterLabel = filterLabel
    self.searchLabel = searchLabel
    self.searchPrompt = searchPrompt
    self.rows = rows
  }

  /// The row a block is listed under, if the filters leave it.
  public func row(containing block: SegmentID) -> BlockRowData? {
    rows.first { $0.members.contains(block) }
  }
}

/// One row of the blocks table: one block, or every tool definition one
/// server offers.
public struct BlockRowData: Sendable, Hashable, Identifiable {
  /// The first block of the row, which is what selecting the row selects.
  public let id: SegmentID
  /// Every block the row stands for, in reading order.
  public let members: [SegmentID]
  public let kind: Kind?
  public let kindName: String
  public let label: String
  public let size: String
  public let carried: String
  public let used: String
  /// What `used` says, which decides the ink the table sets it in.
  public let use: BlockUse
  public let cost: String

  public init(
    id: SegmentID, members: [SegmentID], kind: Kind?, kindName: String, label: String,
    size: String, carried: String, used: String, use: BlockUse, cost: String
  ) {
    self.id = id
    self.members = members
    self.kind = kind
    self.kindName = kindName
    self.label = label
    self.size = size
    self.carried = carried
    self.used = used
    self.use = use
    self.cost = cost
  }
}

/// The sidebar's account of the selected block or group.
public struct InspectorData: Sendable, Hashable {
  /// The block the buttons act on.
  public let block: SegmentID
  public let kind: Kind?
  public let kindName: String
  public let title: String
  public let facts: [FactData]
  public let textTitle: String
  /// The recorded text, nil until it is read or when nothing was recorded.
  public let text: String?
  public let timelineTitle: String
  public let copyTitle: String

  public init(
    block: SegmentID, kind: Kind?, kindName: String, title: String, facts: [FactData],
    textTitle: String, text: String?, timelineTitle: String, copyTitle: String
  ) {
    self.block = block
    self.kind = kind
    self.kindName = kindName
    self.title = title
    self.facts = facts
    self.textTitle = textTitle
    self.text = text
    self.timelineTitle = timelineTitle
    self.copyTitle = copyTitle
  }
}
