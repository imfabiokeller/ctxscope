internal import CoreGraphics

/// Where each request's column sits across a width: equal columns with a gap
/// between them. The plot, the cost
/// bars, the prompt bands and the request numbers all place themselves with
/// this, so a band stands exactly over its columns.
///
/// Hit testing is arithmetic on the column index, never a search.
struct ColumnLayout: Sendable, Hashable {
  let width: CGFloat
  let count: Int
  let gap: CGFloat
  let columnWidth: CGFloat

  /// The full gap while columns have room for it; past that the gap is a
  /// share of a column's pitch, so a few hundred columns still fit.
  init(width: CGFloat, count: Int, metrics: Metrics.Timeline) {
    self.width = max(0, width)
    self.count = max(0, count)
    let pitch = self.count > 0 ? self.width / CGFloat(self.count) : 0
    gap = self.count > 1 ? min(metrics.columnGap, pitch * metrics.columnGapShare) : 0
    columnWidth =
      self.count > 0
      ? max(0, (self.width - gap * CGFloat(self.count - 1)) / CGFloat(self.count)) : 0
  }

  /// The left edge of a column.
  func x(_ column: Int) -> CGFloat {
    CGFloat(column) * (columnWidth + gap)
  }

  func center(_ column: Int) -> CGFloat {
    x(column) + columnWidth / 2
  }

  /// From the left edge of the first column to the right edge of the last.
  func span(_ columns: ClosedRange<Int>) -> (x: CGFloat, width: CGFloat) {
    let left = x(columns.lowerBound)
    return (left, x(columns.upperBound) + columnWidth - left)
  }

  /// The column under a point, a gap counting as the column on its left.
  /// Nil outside the columns.
  func column(atX position: CGFloat) -> Int? {
    guard count > 0, position >= 0, position < width else { return nil }
    let pitch = columnWidth + gap
    guard pitch > 0 else { return nil }
    return min(count - 1, Int(position / pitch))
  }
}
