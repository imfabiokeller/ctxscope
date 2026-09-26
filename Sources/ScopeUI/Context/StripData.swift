public import ScopeCore

/// The context in reading order, as the strip draws it: one slice per block
/// on a scale of tokens, the two marks above it, and the selected span.
public struct StripData: Sendable {
  public let title: String
  /// "0 → 200k tokens".
  public let scaleNote: String
  /// Tokens across the strip's whole width: the window.
  public let scale: Int
  /// In reading order, each starting where the one before it ends.
  public let slices: [StripSlice]
  /// Where the part sent with every request ends.
  public let prefix: StripMark?
  /// Where what was read from the cache ends.
  public let cache: StripMark?
  /// The tokens the selection covers, when it is in this request.
  public let selected: Range<Int>?
  /// The magnifier's heading: "Request 87", and "142.6k · $0.058" beside it.
  public let request: String
  public let figures: String

  public init(
    title: String, scaleNote: String, scale: Int, slices: [StripSlice], prefix: StripMark?,
    cache: StripMark?, selected: Range<Int>?, request: String, figures: String
  ) {
    self.request = request
    self.figures = figures
    self.title = title
    self.scaleNote = scaleNote
    self.scale = max(1, scale)
    self.slices = slices
    self.prefix = prefix
    self.cache = cache
    self.selected = selected
  }

  /// The slice under a position in tokens, found by a binary search over the
  /// slices' starts: a pointer moving over a strip of a few thousand blocks
  /// costs a dozen comparisons, not a pass over all of them. Nil past the
  /// last block.
  public func slice(at token: Double) -> Int? {
    guard let last = slices.last, token >= 0, token < Double(last.end) else { return nil }
    var low = 0
    var high = slices.count - 1
    while low < high {
      let middle = (low + high + 1) / 2
      if Double(slices[middle].start) <= token { low = middle } else { high = middle - 1 }
    }
    return low
  }

  /// The slices around one, `count` of them where there are that many, with
  /// the one in the middle where it can be.
  public func neighborhood(of index: Int, count: Int) -> Range<Int> {
    guard !slices.isEmpty, count > 0 else { return 0..<0 }
    let size = min(count, slices.count)
    let start = max(0, min(slices.count - size, index - size / 2))
    return start..<(start + size)
  }
}

/// One block on the strip.
public struct StripSlice: Sendable, Hashable {
  public let id: SegmentID
  public let start: Int
  public let tokens: Int
  public let grade: Grade
  /// Nil for the untyped remainder.
  public let kind: Kind?
  public let label: String

  public init(
    id: SegmentID, start: Int, tokens: Int, grade: Grade, kind: Kind?, label: String
  ) {
    self.id = id
    self.start = start
    self.tokens = tokens
    self.grade = grade
    self.kind = kind
    self.label = label
  }

  public var end: Int { start + tokens }
  /// "~14.2k", written when the magnifier shows the slice rather than for
  /// every block whenever the page is built.
  public var size: String { UIFormat.tokens(Tokens(tokens, grade)) }
}

/// A mark above the strip, at a position in tokens, with what it says.
public struct StripMark: Sendable, Hashable {
  public let at: Int
  public let label: String

  public init(at: Int, label: String) {
    self.at = at
    self.label = label
  }
}
