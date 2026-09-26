/// Everything the Timeline page shows, as plain values: every word and every
/// figure is already written. `TimelinePresenter` makes one from a lane's
/// analyses; the snapshot tool's sample builds one by hand.
public struct TimelineData: Sendable {
  /// "87 requests · $3.94", for the header's far end.
  public let headerNote: String
  public let chart: TimelineChart
  public let prompts: [PromptRow]
  public let breaks: BreakList
  /// The selected prompt's facts, nil when no prompt is selected.
  public let detail: PromptDetail?

  public init(
    headerNote: String, chart: TimelineChart, prompts: [PromptRow], breaks: BreakList,
    detail: PromptDetail?
  ) {
    self.headerNote = headerNote
    self.chart = chart
    self.prompts = prompts
    self.breaks = breaks
    self.detail = detail
  }
}

/// One typed prompt: its band above the chart and its row in the table.
public struct PromptRow: Sendable, Hashable, Identifiable {
  /// The prompt's number, from one.
  public let id: Int
  /// The requests it spans, as indices from zero, both ends included.
  public let requests: ClosedRange<Int>
  public let isSelected: Bool
  public let number: String
  public let prompt: String
  /// "55–63"
  public let range: String
  public let added: String
  public let cost: String
  public let breaks: String

  public init(
    id: Int, requests: ClosedRange<Int>, isSelected: Bool, number: String, prompt: String,
    range: String, added: String, cost: String, breaks: String
  ) {
    self.id = id
    self.requests = requests
    self.isSelected = isSelected
    self.number = number
    self.prompt = prompt
    self.range = range
    self.added = added
    self.cost = cost
    self.breaks = breaks
  }
}

/// The sidebar's cache breaks: the count, what they added, one card each.
public struct BreakList: Sendable, Hashable {
  /// "3"
  public let count: String
  /// "+$0.83", set strong, then "this session".
  public let extra: String
  public let suffix: String
  public let cards: [BreakCard]

  public init(count: String, extra: String, suffix: String, cards: [BreakCard]) {
    self.count = count
    self.extra = extra
    self.suffix = suffix
    self.cards = cards
  }
}

public struct BreakCard: Sendable, Hashable, Identifiable {
  /// The number its badge and its mark on the chart share.
  public let id: Int
  /// "Request 23 · prompt 4"
  public let place: String
  /// "+$0.17"
  public let extra: String
  /// "Memory changed"
  public let title: String
  public let detail: String

  public init(id: Int, place: String, extra: String, title: String, detail: String) {
    self.id = id
    self.place = place
    self.extra = extra
    self.title = title
    self.detail = detail
  }
}

/// The selected prompt, under the cache breaks.
public struct PromptDetail: Sendable, Hashable {
  /// "7", on the chip that heads the detail, and "requests 55–63" beside it.
  public let number: String
  public let requests: String
  public let prompt: String
  /// In order: context, cost, per request, cache breaks, largest addition.
  public let facts: [FactData]
  /// "Show context at request 63"
  public let link: String
  /// The request index the link opens the context at.
  public let linkRequest: Int

  public init(
    number: String, requests: String, prompt: String, facts: [FactData], link: String,
    linkRequest: Int
  ) {
    self.number = number
    self.requests = requests
    self.prompt = prompt
    self.facts = facts
    self.link = link
    self.linkRequest = linkRequest
  }
}
