public import ScopeCore

public struct ContextPageData: Sendable {
  public var cards: [SummaryCardData]
  public var strip: StripData
  public var legend: [LegendEntryData]
  public var blocks: BlocksData
  public var inspector: InspectorData?
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

public struct BlocksData: Sendable {
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

  public func row(containing block: SegmentID) -> BlockRowData? {
    rows.first { $0.members.contains(block) }
  }
}

public struct BlockRowData: Sendable, Hashable, Identifiable {
  public let id: SegmentID
  public let members: [SegmentID]
  public let kind: Kind?
  public let kindName: String
  public let label: String
  public let size: String
  public let carried: String
  public let used: String
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

public struct InspectorData: Sendable, Hashable {
  public let block: SegmentID
  public let kind: Kind?
  public let kindName: String
  public let title: String
  public let facts: [FactData]
  public let textTitle: String
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
