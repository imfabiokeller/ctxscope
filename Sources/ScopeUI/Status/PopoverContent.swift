public import ScopeCore

/// What the menu bar popover shows, as plain words and shares.
///
/// Worked out by `PopoverPresenter` from the analyses, and drawn by
/// `StatusPopover`, which formats nothing and measures nothing. A value, so a
/// snapshot can fill it with sample numbers and a test can read it.
public enum PopoverContent: Sendable, Equatable {
  /// A session is in focus.
  case focused(FocusedPopover)
  /// None is, and the popover says how to pick one.
  case empty(EmptyPopover)
}

/// The popover of a session in focus.
public struct FocusedPopover: Sendable, Equatable {
  /// One kind: its share of the window, which is its part of the meter, and
  /// its size, which the legend writes beside its name.
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

  /// A figure in the list: "This request", "$0.058". The note follows the
  /// value in quieter type: "· $1.12".
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

  /// The most recent cache break.
  public struct CacheBreak: Sendable, Equatable {
    /// "23 requests ago".
    public let ago: String
    /// "Request 64 · tool definitions changed".
    public let line: String
    /// "+$0.39".
    public let extra: String

    public init(ago: String, line: String, extra: String) {
      self.ago = ago
      self.line = line
      self.extra = extra
    }
  }

  /// "retry-policy".
  public let title: String
  /// "main lane".
  public let lane: String
  public let isLive: Bool
  /// "~/code/api-client · request 87 · 12 s ago".
  public let meta: String
  /// "142.6k", and "of 200k · 71%" beside it.
  public let size: String
  public let sizeNote: String
  /// All six kinds, in reading order.
  public let kinds: [KindPart]
  public let figures: [Figure]
  public let lastBreak: CacheBreak?
  /// "1 → 87".
  public let sparkRange: String
  public let spark: [SparkBar]
  /// The sessions "Change session…" offers.
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

/// The popover when no session is in focus.
public struct EmptyPopover: Sendable, Equatable {
  /// What to type in a chat to focus it: "/ctxscope".
  public let command: String
  public let recent: [RecentSession]

  public init(command: String, recent: [RecentSession]) {
    self.command = command
    self.recent = recent
  }
}

/// A session somebody can pick: its name, where it is and how long it is,
/// and when it was last written.
public struct RecentSession: Sendable, Equatable, Identifiable {
  public let id: String
  /// "retry-policy".
  public let name: String
  /// "~/code/api-client · 87 requests".
  public let detail: String
  /// "2 min ago".
  public let ago: String

  public init(id: String, name: String, detail: String, ago: String) {
    self.id = id
    self.name = name
    self.detail = detail
    self.ago = ago
  }
}

/// What the popover's buttons do. The popover only says which was pressed.
public struct PopoverActions {
  public var openWindow: () -> Void
  /// Focus this session, by id.
  public var pick: (String) -> Void
  /// Put this text on the pasteboard.
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
