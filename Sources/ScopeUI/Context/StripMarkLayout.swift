internal import CoreGraphics

struct StripMarkLayout: Equatable {
  var prefixLabel: CGFloat?
  var cacheLabel: CGFloat?
  var crossesBracketEdge = false
  var crossesCacheLine = false

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
