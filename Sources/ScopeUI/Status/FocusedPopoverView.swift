internal import ScopeCore
internal import SwiftUI

struct FocusedPopoverView: View {
  let content: FocusedPopover
  let actions: PopoverActions
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PopoverTitle(content: content)
      PopoverSize(content: content)
      Hairline(.divider)
      DefinitionList(content.figures.map(entry))
        .padding(theme.metrics.popover.section)
      if let lastBreak = content.lastBreak {
        Hairline(.divider)
        PopoverBreak(lastBreak: lastBreak)
      }
      Hairline(.divider)
      PopoverSpark(range: content.sparkRange, bars: content.spark)
        .contentShape(Rectangle())
        .onTapGesture(perform: actions.openWindow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Context per request, \(content.sparkRange)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open window", actions.openWindow)
      FocusedFooter(others: content.others, actions: actions)
    }
  }

  private func entry(_ figure: FocusedPopover.Figure) -> DefinitionList.Entry {
    guard let note = figure.note else { return DefinitionList.Entry(figure.term, figure.value) }
    let quiet = Text(" " + note).font(theme.type.body).foregroundStyle(theme.text.secondary.color)
    return DefinitionList.Entry(figure.term, Text(figure.value) + quiet)
  }
}

private struct PopoverTitle: View {
  let content: FocusedPopover
  @Environment(\.theme) private var theme

  var body: some View {
    let popover = theme.metrics.popover
    let lines = theme.type.lines
    VStack(alignment: .leading, spacing: popover.titleGap) {
      HStack(spacing: popover.titleRowGap) {
        Text(content.title)
          .font(theme.type.bodyStrong)
          .foregroundStyle(theme.text.primary.color)
          .lineLimit(1)
        Text(content.lane)
          .font(theme.type.caption)
          .foregroundStyle(theme.text.secondary.color)
          .lineLimit(1)
          .layoutPriority(-1)
        Spacer(minLength: 0)
        if content.isLive { StatusDot().line(lines.small) }
      }
      .line(lines.body)
      Text(content.meta)
        .font(theme.type.caption)
        .foregroundStyle(theme.text.secondary.color)
        .lineLimit(1)
        .truncationMode(.middle)
        .line(lines.caption)
    }
    .padding(popover.titlePadding)
  }
}

private struct PopoverSize: View {
  let content: FocusedPopover
  @Environment(\.theme) private var theme

  var body: some View {
    let popover = theme.metrics.popover
    VStack(alignment: .leading, spacing: popover.sizeGap) {
      HStack(alignment: .firstTextBaseline, spacing: popover.figureGap) {
        Text(content.size)
          .font(theme.type.popoverFigure)
          .tracking(theme.type.popoverFigureTracking)
          .foregroundStyle(theme.text.primary.color)
          .line(theme.type.lines.figure)
        Text(content.sizeNote)
          .font(theme.type.popoverFigureNote)
          .foregroundStyle(theme.text.secondary.color)
          .line(theme.type.lines.note)
      }
      .accessibilityElement(children: .combine)
      Meter(
        content.kinds.map { Meter.Part(color: theme.kind.color(of: $0.kind), share: $0.share) })
      legend
    }
    .padding(popover.sizePadding)
  }

  private var legend: some View {
    let popover = theme.metrics.popover
    let rows = stride(from: 0, to: content.kinds.count, by: popover.legendColumns).map {
      Array(content.kinds[$0..<min($0 + popover.legendColumns, content.kinds.count)])
    }
    return VStack(alignment: .leading, spacing: popover.legendRowGap) {
      ForEach(rows.indices, id: \.self) { row in
        HStack(spacing: popover.legendColumnGap) {
          ForEach(rows[row], id: \.kind) { part in
            KindLegendItem(
              color: theme.kind.color(of: part.kind), name: part.kind.rawValue,
              detail: part.size, style: .compact
            )
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .line(theme.type.lines.small)
      }
    }
  }
}

private struct PopoverBreak: View {
  let lastBreak: FocusedPopover.CacheBreak
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: theme.metrics.popover.breakGap) {
      HStack(alignment: .firstTextBaseline) {
        Text("Last cache break")
        Spacer(minLength: 0)
        Text(lastBreak.ago)
      }
      .line(theme.type.lines.caption)
      .font(theme.type.caption)
      .foregroundStyle(theme.text.secondary.color)
      HStack(alignment: .firstTextBaseline) {
        Text(lastBreak.line).font(theme.type.body).lineLimit(1)
        Spacer(minLength: 0)
        Text(lastBreak.extra).font(theme.type.bodyStrong)
      }
      .line(theme.type.lines.body)
      .foregroundStyle(theme.text.primary.color)
    }
    .padding(theme.metrics.popover.section)
    .accessibilityElement(children: .combine)
  }
}

private struct PopoverSpark: View {
  let range: String
  let bars: [SparkBar]
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(spacing: theme.metrics.popover.sparkGap) {
      HStack {
        Text("Context per request")
        Spacer(minLength: 0)
        Text(range)
      }
      .line(theme.type.lines.caption)
      .font(theme.type.caption)
      .foregroundStyle(theme.text.secondary.color)
      Sparkline(bars.map { Sparkline.Bar(height: $0.height, isMarked: $0.isBreak) })
    }
    .padding(theme.metrics.popover.section)
  }
}
