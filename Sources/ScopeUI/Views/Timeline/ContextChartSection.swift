internal import SwiftUI

/// "Context per request": the legend, the prompt bands, the plot with its
/// axis, the cost bars and the request numbers. Every row after the legend
/// leaves the axis's width on its left, so all of them share one column
/// layout.
struct ContextChartSection: View {
  let chart: TimelineChart
  let prompts: [PromptRow]
  let onSelectPrompt: (Int) -> Void
  let onPickColumn: (Int) -> Void
  /// Where the pointer starts over the plot, for a picture of the magnifier.
  var hover: ColumnHover?
  @Environment(\.theme) private var theme

  private var metrics: Metrics.Timeline { theme.metrics.timeline }

  var body: some View {
    VStack(alignment: .leading, spacing: metrics.chartGap) {
      SectionHeader(TimelineWords.chart) {
        ForEach(theme.kind.named, id: \.name) { kind in
          KindLegendItem(color: kind.color, name: kind.name, style: .plain)
        }
        HStack(spacing: theme.metrics.swatch.legendGap) {
          DashedRule(theme.chart.marker).frame(height: metrics.legendMarkerHeight)
          Text(TimelineWords.cacheBreak).font(theme.type.caption)
            .foregroundStyle(theme.text.primary.color)
        }
        .fixedSize()
      }
      .frame(height: metrics.legendHeight)
      row(height: metrics.bandHeight) { layout in
        PromptBands(prompts: prompts, layout: layout, onSelect: onSelectPrompt)
      }
      row(height: metrics.plotHeight, leading: TokenAxis(ticks: chart.tokenTicks)) { layout in
        ContextPlot(chart: chart, layout: layout, hover: hover, onPick: onPickColumn)
      }
      .zIndex(1)
      row(
        height: metrics.costHeight + theme.metrics.hairline,
        leading: Text(TimelineWords.cost).font(theme.type.axis)
          .foregroundStyle(theme.text.secondary.color)
          .padding(.top, metrics.costLabelInset)
      ) { layout in
        CostBars(chart: chart, layout: layout)
      }
      row(height: metrics.axisLineHeight) { layout in
        RequestAxis(ticks: chart.requestTicks, layout: layout)
      }
    }
  }

  /// A row of the chart: the axis's column, then the columns' width, which
  /// is what the layout is made for.
  private func row(
    height: CGFloat?, leading: some View = EmptyView(),
    @ViewBuilder content: @escaping (ColumnLayout) -> some View
  ) -> some View {
    HStack(alignment: .top, spacing: metrics.axisGap) {
      Spacer(minLength: 0)
        .frame(width: metrics.axisWidth)
        .overlay(alignment: .topTrailing) { leading }
      GeometryReader { proxy in
        content(ColumnLayout(width: proxy.size.width, count: chart.columns.count, metrics: metrics))
      }
    }
    .frame(height: height)
  }
}
