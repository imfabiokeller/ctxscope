public import ScopeCore

public struct StripData: Sendable {
  public let title: String
  public let scaleNote: String
  public let scale: Int
  public let slices: [StripSlice]
  public let prefix: StripMark?
  public let cache: StripMark?
  public let selected: Range<Int>?
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

  public func neighborhood(of index: Int, count: Int) -> Range<Int> {
    guard !slices.isEmpty, count > 0 else { return 0..<0 }
    let size = min(count, slices.count)
    let start = max(0, min(slices.count - size, index - size / 2))
    return start..<(start + size)
  }
}

public struct StripSlice: Sendable, Hashable {
  public let id: SegmentID
  public let start: Int
  public let tokens: Int
  public let grade: Grade
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
  public var size: String { UIFormat.tokens(Tokens(tokens, grade)) }
}

public struct StripMark: Sendable, Hashable {
  public let at: Int
  public let label: String

  public init(at: Int, label: String) {
    self.at = at
    self.label = label
  }
}
