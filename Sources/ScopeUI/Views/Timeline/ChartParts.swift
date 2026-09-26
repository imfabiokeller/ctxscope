internal import SwiftUI

/// A bar per request for what its context cost, a cache break's bar darker,
/// on a rule, faded with its column.
struct CostBars: View {
  let chart: TimelineChart
  let layout: ColumnLayout
  @Environment(\.theme) private var theme

  var body: some View {
    let metrics = theme.metrics.timeline
    let hairline = theme.metrics.hairline
    Canvas { context, size in
      let height = size.height - hairline
      for (column, cost) in chart.costs.enumerated() {
        let bar = max(metrics.costMinimum, cost.share * height)
        let shape = UnevenRoundedRectangle(
          topLeadingRadius: metrics.costRadius, topTrailingRadius: metrics.costRadius)
        let color = cost.isBreak ? theme.chart.costBreak : theme.chart.cost
        context.fill(
          shape.path(
            in: CGRect(x: layout.x(column), y: height - bar, width: layout.columnWidth, height: bar)
          ),
          with: .color(
            color.opacity(chart.isHighlighted(column) ? 1 : theme.chart.dimmedOpacity).color))
      }
      context.fill(
        Path(CGRect(x: 0, y: height, width: size.width, height: hairline)),
        with: .color(theme.chart.gridStrong.color))
    }
    .frame(width: layout.width, height: metrics.costHeight + hairline)
    .accessibilityHidden(true)
  }
}

/// Labels up the side of the plot, each centered on its gridline.
struct TokenAxis: View {
  let ticks: [TimelineChart.Tick]
  @Environment(\.theme) private var theme

  var body: some View {
    let metrics = theme.metrics.timeline
    ZStack {
      ForEach(ticks, id: \.self) { tick in
        Text(tick.label)
          .frame(width: metrics.axisWidth, alignment: .trailing)
          .position(x: metrics.axisWidth / 2, y: (1 - tick.position) * metrics.plotHeight)
      }
    }
    .font(theme.type.axis)
    .foregroundStyle(theme.text.secondary.color)
    .frame(width: metrics.axisWidth, height: metrics.plotHeight, alignment: .topTrailing)
    .accessibilityHidden(true)
  }
}

/// Request numbers under their columns, the first and the last held inside
/// the plot's width.
struct RequestAxis: View {
  let ticks: [TimelineChart.Tick]
  let layout: ColumnLayout
  @Environment(\.theme) private var theme

  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(ticks, id: \.self) { tick in
        Text(tick.label)
          .fixedSize()
          .frame(height: theme.metrics.timeline.axisLineHeight)
          .alignmentGuide(.leading) { size in
            let center = layout.center(Int(tick.position))
            return -min(max(0, center - size.width / 2), max(0, layout.width - size.width))
          }
      }
    }
    .font(theme.type.axis)
    .foregroundStyle(theme.text.secondary.color)
    .frame(width: layout.width, alignment: .topLeading)
    .accessibilityHidden(true)
  }
}
