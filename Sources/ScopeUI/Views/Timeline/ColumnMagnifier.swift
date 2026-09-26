public import SwiftUI

/// The hovered request's column at height, every block in it a slice, beside
/// a window of its blocks as rows: swatch, label, size. The block under the
/// pointer is outlined in the column and marked in the rows, and the window
/// follows it; with no block under the pointer it shows the top of the column.
public struct ColumnMagnifier: View {
  private let chart: TimelineChart
  private let column: Int
  private let slice: Int?
  @Environment(\.theme) private var theme
  @Environment(\.displayScale) private var displayScale

  /// `slice` is the block under the pointer, as an index into the column's
  /// slices.
  public init(chart: TimelineChart, column: Int, slice: Int?) {
    self.chart = chart
    self.column = column
    self.slice = slice
  }

  private var metrics: Metrics.Magnifier { theme.metrics.magnifier }
  private var slices: [TimelineChart.Slice] { chart.columns[column].slices }

  /// The rows shown, bottom block first: a window of rows centered on the
  /// block under the pointer, kept inside the column.
  private var window: ClosedRange<Int>? {
    guard !slices.isEmpty else { return nil }
    let center = slice ?? slices.count - 1
    let first = max(0, min(slices.count - metrics.rows, center - metrics.rows / 2))
    return first...min(slices.count - 1, first + metrics.rows - 1)
  }

  public var body: some View {
    let entry = chart.columns[column]
    VStack(alignment: .leading, spacing: 0) {
      MagnifierHeader(
        title: entry.title, figures: entry.figures,
        window: window.map {
          MagnifierWords.window($0.lowerBound..<($0.upperBound + 1), of: slices.count)
        })
      HStack(alignment: .top, spacing: metrics.gap) {
        Canvas { context, size in draw(in: &context, size: size) }
          .frame(width: metrics.columnWidth, height: metrics.columnHeight)
          .clipShape(RoundedRectangle(cornerRadius: metrics.columnRadius))
        VStack(spacing: 0) {
          ForEach((window ?? 0...(-1)).reversed(), id: \.self) { row($0) }
        }
        .frame(height: metrics.columnHeight)
      }
    }
    .foregroundStyle(theme.text.primary.color)
    .padding(.vertical, metrics.padding.vertical)
    .padding(.horizontal, metrics.padding.horizontal)
    .frame(width: metrics.width)
    .background {
      let shadow = theme.shadow.popover
      RoundedRectangle(cornerRadius: metrics.cornerRadius)
        .fill(theme.surface.popover.color)
        .shadow(color: shadow.color.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
    .overlay {
      RoundedRectangle(cornerRadius: metrics.cornerRadius)
        .strokeBorder(theme.line.popover.color, lineWidth: theme.metrics.hairline)
    }
  }

  private func row(_ index: Int) -> some View {
    let block = chart.blocks[Int(slices[index].block)]
    return MagnifierRow(
      color: theme.color(of: block.kind), label: block.label, size: block.size,
      isHovered: index == slice)
  }

  /// The column scaled to the magnifier's height, the rows' window bracketed
  /// and the hovered block outlined.
  private func draw(in context: inout GraphicsContext, size: CGSize) {
    let total = CGFloat(chart.columns[column].end)
    guard total > 0 else { return }
    let perToken = size.height / total
    func rect(_ range: ClosedRange<Int>) -> CGRect {
      let bottom = size.height - CGFloat(slices[range.lowerBound].start) * perToken
      let top = size.height - CGFloat(slices[range.upperBound].end) * perToken
      return CGRect(x: 0, y: top, width: size.width, height: bottom - top)
    }
    let timeline = theme.metrics.timeline
    var below: CGFloat?
    for (index, entry) in slices.enumerated() {
      let kind = chart.blocks[Int(entry.block)].kind
      let area = rect(index...index)
      context.fill(Path(area), with: .color(theme.color(of: kind).color))
      defer { below = area.height }
      // The same rule between blocks as the plot's, by the same measure.
      if let below,
        timeline.separates(below: below * displayScale, above: area.height * displayScale)
      {
        context.fill(
          Path(
            CGRect(
              x: 0, y: area.maxY - timeline.blockGap, width: size.width, height: timeline.blockGap)),
          with: .color(theme.chart.blockGap.color))
      }
    }
    let line = theme.metrics.hairline
    if let window {
      context.stroke(
        Path(rect(window).insetBy(dx: line / 2, dy: line / 2)),
        with: .color(theme.chart.marker.color), lineWidth: line)
    }
    if let slice {
      context.stroke(
        Path(rect(slice...slice).insetBy(dx: line, dy: 0)),
        with: .color(theme.chart.marker.color), lineWidth: line * 2)
    }
  }
}
