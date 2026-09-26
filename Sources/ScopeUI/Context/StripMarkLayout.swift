internal import CoreGraphics

/// Where the two marks' labels stand above the strip, worked out from where
/// the marks are and how wide their labels are. A pure function, so that the
/// labels never overlapping each other or a mark is tested without drawing.
///
/// The bracket's label starts inside the bracket, and
/// the bracket keeps its width however long the label is. The cache label
/// stands right of its line, moved right past the bracket's label when the
/// two would meet, or left of its line when the right has no room. A mark's
/// upright that a label runs across starts under the labels, so no text is
/// struck through.
struct StripMarkLayout: Equatable {
  /// Where each label starts, when there is one.
  var prefixLabel: CGFloat?
  var cacheLabel: CGFloat?
  /// True when a label runs across the bracket's closing edge.
  var crossesBracketEdge = false
  /// True when a label runs across the cache line.
  var crossesCacheLine = false

  /// `prefixEnd` is where the bracket ends and `cacheAt` where the cache line
  /// stands, both from the strip's leading edge; the widths are the labels'.
  /// `inset` is a label's distance from the mark it belongs to, past the
  /// cache line's width `line`, and `gap` the least room between the two
  /// labels.
  static func place(
    width: CGFloat, prefixEnd: CGFloat?, prefixWidth: CGFloat, cacheAt: CGFloat?,
    cacheWidth: CGFloat, inset: CGFloat, line: CGFloat = 0, gap: CGFloat
  ) -> StripMarkLayout {
    var layout = StripMarkLayout()
    var taken: ClosedRange<CGFloat>?
    if prefixEnd != nil {
      layout.prefixLabel = inset
      taken = inset...(inset + prefixWidth)
    }
    if let cacheAt {
      var start = cacheAt + line + inset
      if let taken, start < taken.upperBound + gap, start + cacheWidth > taken.lowerBound - gap {
        start = taken.upperBound + gap
      }
      if start + cacheWidth > width {
        let before = cacheAt - inset - cacheWidth
        let clear = taken.map {
          before + cacheWidth + gap <= $0.lowerBound || before >= $0.upperBound + gap
        }
        if before >= 0, clear ?? true { start = before }
      }
      layout.cacheLabel = start
    }
    let labels = [taken, layout.cacheLabel.map { $0...($0 + cacheWidth) }].compactMap(\.self)
    func crossed(_ x: CGFloat?) -> Bool {
      guard let x else { return false }
      return labels.contains { $0.lowerBound < x && x < $0.upperBound }
    }
    layout.crossesBracketEdge = crossed(prefixEnd)
    layout.crossesCacheLine = crossed(cacheAt)
    return layout
  }
}
