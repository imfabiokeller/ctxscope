public import ScopeCore

public struct TimelineChart: Sendable {
  public struct Block: Sendable, Hashable {
    public let label: String
    public let kind: Kind?
    public let size: String

    public init(label: String, kind: Kind?, size: String) {
      self.label = label
      self.kind = kind
      self.size = size
    }
  }

  public struct Slice: Sendable, Hashable {
    public let block: Int32
    public let start: Int32
    public let tokens: Int32

    public init(block: Int, start: Int, tokens: Int) {
      self.block = Int32(clamping: block)
      self.start = Int32(clamping: start)
      self.tokens = Int32(clamping: tokens)
    }

    public var end: Int { Int(start) + Int(tokens) }
  }

  public struct Column: Sendable, Hashable {
    public let slices: [Slice]
    public let title: String
    public let figures: String

    public init(slices: [Slice], title: String, figures: String) {
      self.slices = slices
      self.title = title
      self.figures = figures
    }

    public var end: Int { slices.last?.end ?? 0 }

    public func slice(atTokens tokens: Int) -> Int? {
      guard let last = slices.last, tokens >= 0, tokens < last.end else { return nil }
      var low = 0
      var high = slices.count - 1
      while low < high {
        let middle = (low + high + 1) / 2
        if Int(slices[middle].start) <= tokens { low = middle } else { high = middle - 1 }
      }
      return low
    }
  }

  public struct Break: Sendable, Hashable {
    public let column: Int
    public let number: Int

    public init(column: Int, number: Int) {
      self.column = column
      self.number = number
    }
  }

  public struct Cost: Sendable, Hashable {
    public let share: Double
    public let isBreak: Bool

    public init(share: Double, isBreak: Bool) {
      self.share = share
      self.isBreak = isBreak
    }
  }

  public struct Tick: Sendable, Hashable {
    public let label: String
    public let position: Double

    public init(_ label: String, at position: Double) {
      self.label = label
      self.position = position
    }
  }

  /// Charts with the same identity draw the same columns, so one drawing serves both.
  public let identity: Int
  public let scale: Int
  public let blocks: [Block]
  public let columns: [Column]
  public let breaks: [Break]
  public let costs: [Cost]
  public let tokenTicks: [Tick]
  public let requestTicks: [Tick]
  public let highlighted: ClosedRange<Int>?

  public init(
    identity: Int, scale: Int, blocks: [Block], columns: [Column], breaks: [Break],
    costs: [Cost], tokenTicks: [Tick], requestTicks: [Tick], highlighted: ClosedRange<Int>?
  ) {
    self.identity = identity
    self.scale = scale
    self.blocks = blocks
    self.columns = columns
    self.breaks = breaks
    self.costs = costs
    self.tokenTicks = tokenTicks
    self.requestTicks = requestTicks
    self.highlighted = highlighted
  }

  public func isHighlighted(_ column: Int) -> Bool {
    highlighted?.contains(column) ?? true
  }
}
