public struct TimelineData: Sendable {
  public let headerNote: String
  public let chart: TimelineChart
  public let prompts: [PromptRow]
  public let breaks: BreakList
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

public struct PromptRow: Sendable, Hashable, Identifiable {
  public let id: Int
  public let requests: ClosedRange<Int>
  public let isSelected: Bool
  public let number: String
  public let prompt: String
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

public struct BreakList: Sendable, Hashable {
  public let count: String
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
  public let id: Int
  public let place: String
  public let extra: String
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

public struct PromptDetail: Sendable, Hashable {
  public let number: String
  public let requests: String
  public let prompt: String
  public let facts: [FactData]
  public let link: String
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
