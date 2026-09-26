public import ScopeCore

/// The "Context per request" chart as plain values: one column per request,
/// every block a slice of it, and what is drawn around the columns.
///
/// Blocks are listed once and a column's slices point into that list, so a
/// lane of a few hundred requests over a few thousand blocks keeps each label
/// once rather than once per column it is in.
public struct TimelineChart: Sendable {
  /// One block, as the magnifier names it.
  public struct Block: Sendable, Hashable {
    public let label: String
    /// Nil for unattributed tokens, drawn as an untyped remainder.
    public let kind: Kind?
    /// "~1.2k", with its mark when estimated.
    public let size: String

    public init(label: String, kind: Kind?, size: String) {
      self.label = label
      self.kind = kind
      self.size = size
    }
  }

  /// One block in one column, in tokens from the bottom of the column.
  public struct Slice: Sendable, Hashable {
    /// Where the block is in `blocks`.
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
    /// In reading order, the first at the bottom.
    public let slices: [Slice]
    /// "Request 64", heading the magnifier.
    public let title: String
    /// "95.7k · $0.05"
    public let figures: String

    public init(slices: [Slice], title: String, figures: String) {
      self.slices = slices
      self.title = title
      self.figures = figures
    }

    public var end: Int { slices.last?.end ?? 0 }

    /// The slice at a height in tokens, by binary search over the starts.
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

  /// A cache break's mark: which column, and the number its card carries.
  public struct Break: Sendable, Hashable {
    public let column: Int
    public let number: Int

    public init(column: Int, number: Int) {
      self.column = column
      self.number = number
    }
  }

  /// A request's cost bar.
  public struct Cost: Sendable, Hashable {
    /// Of the most expensive request's, from 0 to 1.
    public let share: Double
    public let isBreak: Bool

    public init(share: Double, isBreak: Bool) {
      self.share = share
      self.isBreak = isBreak
    }
  }

  /// A label along an axis, and where it belongs: a request index along the
  /// bottom, a share of the height up the side.
  public struct Tick: Sendable, Hashable {
    public let label: String
    public let position: Double

    public init(_ label: String, at position: Double) {
      self.label = label
      self.position = position
    }
  }

  /// What the columns are: two charts with the same identity draw the same
  /// columns, so a drawing of one serves the other.
  public let identity: Int
  /// The tokens the full height stands for.
  public let scale: Int
  public let blocks: [Block]
  public let columns: [Column]
  public let breaks: [Break]
  public let costs: [Cost]
  /// Bottom to top, positions as a share of the height.
  public let tokenTicks: [Tick]
  /// Left to right, positions as request indices.
  public let requestTicks: [Tick]
  /// The columns drawn at full strength. Nil draws them all that way.
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

  /// Whether a column is drawn at full strength.
  public func isHighlighted(_ column: Int) -> Bool {
    highlighted?.contains(column) ?? true
  }
}
