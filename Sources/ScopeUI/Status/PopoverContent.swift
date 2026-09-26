public import ScopeCore

public enum PopoverContent: Sendable, Equatable {
  case focused(FocusedPopover)
  case empty(EmptyPopover)
}

public struct FocusedPopover: Sendable, Equatable {
  public struct KindPart: Sendable, Equatable {
    public let kind: Kind
    public let share: Double
    public let size: String

    public init(kind: Kind, share: Double, size: String) {
      self.kind = kind
      self.share = share
      self.size = size
    }
  }

  public struct Figure: Sendable, Equatable {
    public let term: String
    public let value: String
    public let note: String?

    public init(term: String, value: String, note: String? = nil) {
      self.term = term
      self.value = value
      self.note = note
    }
  }

  public struct CacheBreak: Sendable, Equatable {
    public let ago: String
    public let line: String
    public let extra: String

    public init(ago: String, line: String, extra: String) {
      self.ago = ago
      self.line = line
      self.extra = extra
    }
  }

  public let title: String
  public let lane: String
  public let isLive: Bool
  public let meta: String
  public let size: String
  public let sizeNote: String
  public let kinds: [KindPart]
  public let figures: [Figure]
  public let lastBreak: CacheBreak?
  public let sparkRange: String
  public let spark: [SparkBar]
  public let others: [RecentSession]

  public init(
    title: String, lane: String, isLive: Bool, meta: String, size: String, sizeNote: String,
    kinds: [KindPart], figures: [Figure], lastBreak: CacheBreak?, sparkRange: String,
    spark: [SparkBar], others: [RecentSession]
  ) {
    self.title = title
    self.lane = lane
    self.isLive = isLive
    self.meta = meta
    self.size = size
    self.sizeNote = sizeNote
    self.kinds = kinds
    self.figures = figures
    self.lastBreak = lastBreak
    self.sparkRange = sparkRange
    self.spark = spark
    self.others = others
  }
}

public struct EmptyPopover: Sendable, Equatable {
  public let command: String
  public let recent: [RecentSession]

  public init(command: String, recent: [RecentSession]) {
    self.command = command
    self.recent = recent
  }
}

public struct RecentSession: Sendable, Equatable, Identifiable {
  public let id: String
  public let name: String
  public let detail: String
  public let ago: String

  public init(id: String, name: String, detail: String, ago: String) {
    self.id = id
    self.name = name
    self.detail = detail
    self.ago = ago
  }
}

public struct PopoverActions {
  public var openWindow: () -> Void
  public var pick: (String) -> Void
  public var copy: (String) -> Void
  public var connect: () -> Void
  public var turnOff: () -> Void
  public var quit: () -> Void

  public init(
    openWindow: @escaping () -> Void = {}, pick: @escaping (String) -> Void = { _ in },
    copy: @escaping (String) -> Void = { _ in }, connect: @escaping () -> Void = {},
    turnOff: @escaping () -> Void = {}, quit: @escaping () -> Void = {}
  ) {
    self.openWindow = openWindow
    self.pick = pick
    self.copy = copy
    self.connect = connect
    self.turnOff = turnOff
    self.quit = quit
  }
}
