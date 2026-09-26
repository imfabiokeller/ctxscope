internal import CoreGraphics
internal import ScopeCore
public import SwiftUI

/// The plot of "Context per request": gridlines, one column per request with
/// every block a slice, and a dashed line with its number at each cache
/// break. Hovering a column shows the magnifier; clicking one picks it.
///
/// The columns are one image, kept in a `DrawingCache` and drawn off the main
/// actor. Per frame only the gridlines, the hovered block's outline and the
/// marks are drawn.
struct ContextPlot: View {
  let chart: TimelineChart
  let layout: ColumnLayout
  let onPick: (Int) -> Void
  @State private var cache = DrawingCache<ColumnImage.Key, CGImage>()
  @State private var hover: ColumnHover?
  @Environment(\.theme) private var theme
  @Environment(\.displayScale) private var displayScale
  @Environment(\.isRendering) private var isRendering

  /// `hover` is where the pointer starts, for a picture of the magnifier.
  init(
    chart: TimelineChart, layout: ColumnLayout, hover: ColumnHover? = nil,
    onPick: @escaping (Int) -> Void
  ) {
    self.chart = chart
    self.layout = layout
    self.onPick = onPick
    _hover = State(initialValue: hover)
  }

  private var metrics: Metrics.Timeline { theme.metrics.timeline }

  var body: some View {
    let height = metrics.plotHeight
    let image = columns(height: height)
    Canvas(opaque: false, rendersAsynchronously: false) { context, size in
      drawGrid(in: &context, size: size)
      if let image {
        context.withCGContext { $0.place(image, in: CGRect(origin: .zero, size: size)) }
      }
      if let hover { outline(hover, in: &context, height: size.height) }
    }
    .frame(width: layout.width, height: height)
    .overlay(alignment: .topLeading) { marks(height: height) }
    .contentShape(Rectangle())
    .onContinuousHover { phase in
      switch phase {
      case .active(let point): hover = self.point(at: point, height: height)
      case .ended: hover = nil
      }
    }
    .onTapGesture { point in
      if let column = layout.column(atX: point.x) { onPick(column) }
    }
    .overlay(alignment: .topLeading) {
      if let hover {
        let magnifier = theme.metrics.magnifier
        // Centered on the plot's height, which it is taller than, and beside
        // the pointer on whichever side has room.
        ColumnMagnifier(chart: chart, column: hover.column, slice: hover.slice)
          .fixedSize()
          .frame(width: magnifier.width, height: height)
          .offset(
            x: Self.magnifierX(
              hover.x, width: magnifier.width, offset: magnifier.offset, room: layout.width)
          )
          .allowsHitTesting(false)
      }
    }
    .accessibilityElement()
    .accessibilityLabel("Context per request")
    .accessibilityValue(TokenFormat.plural(chart.columns.count, "request"))
  }

  /// The drawn columns, or nothing for the frame or two a window waits for
  /// them.
  private func columns(height: CGFloat) -> CGImage? {
    let key = ColumnImage.Key(
      chart: chart.identity,
      width: Int((layout.width * displayScale).rounded()),
      height: Int((height * displayScale).rounded()),
      scale: displayScale, theme: theme.hashValue, highlighted: chart.highlighted)
    let chart = chart
    let layout = layout
    let theme = theme
    let metrics = metrics
    return cache.value(for: key, synchronously: isRendering) {
      ColumnImage.make(chart: chart, layout: layout, key: key, theme: theme, metrics: metrics)
    }
  }

  /// Lines at every token tick, the outer two stronger, each inside the
  /// plot's height the way a one point border sits inside its box.
  private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
    let ticks = chart.tokenTicks
    for (index, tick) in ticks.enumerated() {
      let y = (1 - tick.position) * (size.height - theme.metrics.hairline)
      let outer = index == 0 || index == ticks.count - 1
      context.fill(
        Path(CGRect(x: 0, y: y, width: size.width, height: theme.metrics.hairline)),
        with: .color((outer ? theme.chart.gridStrong : theme.chart.gridFaint).color))
    }
  }

  /// The hovered block, outlined in its column.
  private func outline(_ point: ColumnHover, in context: inout GraphicsContext, height: CGFloat) {
    guard let index = point.slice, chart.scale > 0 else { return }
    let slice = chart.columns[point.column].slices[index]
    let perToken = height / CGFloat(chart.scale)
    let rect = CGRect(
      x: layout.x(point.column), y: height - CGFloat(slice.end) * perToken,
      width: layout.columnWidth,
      height: max(theme.metrics.hairline, CGFloat(slice.tokens) * perToken))
    context.stroke(
      Path(rect.insetBy(dx: -0.5, dy: -0.5)), with: .color(theme.chart.marker.color),
      lineWidth: theme.metrics.hairline)
  }

  /// A dashed line from just above the plot to its foot at each cache break,
  /// with its number on top, faded with its column.
  /// Each badge `BreakBadges` groups, over the dashed lines of its breaks
  /// from just above the plot to its foot, faded as one with their columns
  /// so a faded badge does not show its lines through itself. A badge names
  /// its breaks in its tooltip, and a click moves to the first.
  private func marks(height: CGFloat) -> some View {
    let breaks = chart.breaks
    let groups = BreakBadges.group(
      centers: breaks.map { layout.center($0.column) }, numbers: breaks.map(\.number),
      badge: theme.metrics.badge, inset: metrics.badgeInset, gap: metrics.badgeGap,
      total: layout.width, width: MeasuredRole.badge.width(of:))
    return ForEach(groups, id: \.breaks) { group in
      let marks = Array(breaks[group.breaks])
      ZStack(alignment: .topLeading) {
        ForEach(marks, id: \.column) { mark in
          DashedRule(theme.chart.marker)
            .frame(height: height + metrics.markerOverhang)
            .offset(
              x: layout.center(mark.column) - group.x,
              y: metrics.badgeRise - metrics.markerOverhang
            )
            .allowsHitTesting(false)
        }
        Button {
          onPick(marks[0].column)
        } label: {
          NumberBadge(group.label, width: group.width)
        }
        .buttonStyle(.plain)
        .help(TimelineWords.breaks(marks))
      }
      .offset(x: group.x, y: -metrics.badgeRise)
      .compositingGroup()
      .opacity(marks.contains { chart.isHighlighted($0.column) } ? 1 : theme.chart.dimmedOpacity)
    }
  }

  private func point(at location: CGPoint, height: CGFloat) -> ColumnHover? {
    guard let column = layout.column(atX: location.x), height > 0 else { return nil }
    let tokens = Int((height - location.y) / height * CGFloat(chart.scale))
    return ColumnHover(
      column: column, slice: chart.columns[column].slice(atTokens: tokens), x: location.x)
  }

  /// Right of the pointer, or left of it where the right has no room.
  /// Where neither side has room, against the plot's right end, never
  /// past its left.
  nonisolated static func magnifierX(
    _ x: CGFloat, width: CGFloat, offset: CGFloat, room: CGFloat
  ) -> CGFloat {
    if x + offset + width <= room { return x + offset }
    if x - offset - width >= 0 { return x - offset - width }
    return max(0, room - width)
  }
}

/// A column under the pointer, the block under it if any, and where the
/// pointer is across the plot.
public struct ColumnHover: Equatable, Sendable {
  public let column: Int
  public let slice: Int?
  public let x: CGFloat

  public init(column: Int, slice: Int?, x: CGFloat) {
    self.column = column
    self.slice = slice
    self.x = x
  }
}
