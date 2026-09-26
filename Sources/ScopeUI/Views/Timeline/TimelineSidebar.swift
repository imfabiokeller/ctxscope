internal import SwiftUI

/// The Timeline page's sidebar: the cache breaks, one card each, then the
/// selected prompt's facts and the way to its context.
struct TimelineSidebar: View {
  let breaks: BreakList
  let detail: PromptDetail?
  /// What the detail is scrolled to by: the selected prompt's number.
  let detailID: Int?
  let onShowContext: (Int) -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    let metrics = theme.metrics.timeline
    VStack(alignment: .leading, spacing: metrics.sidebarGap) {
      VStack(alignment: .leading, spacing: theme.metrics.card.gap) {
        SectionHeader(
          TimelineWords.breaks,
          detail: Text("\(breaks.count) · ")
            + Text(breaks.extra).font(theme.type.captionStrong) + Text(" \(breaks.suffix)"),
          tone: .supporting
        )
        .frame(height: metrics.headingHeight)
        ForEach(breaks.cards) { BreakCardView(card: $0) }
      }
      Hairline(.divider)
      if let detail {
        PromptDetailView(detail: detail, onShowContext: onShowContext).id(detailID)
      }
    }
    .padding(metrics.sidebarPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// One cache break: its number, where it happened, what it added, why.
private struct BreakCardView: View {
  let card: BreakCard
  @Environment(\.theme) private var theme

  var body: some View {
    let type = theme.type
    Card(.raised) {
      HStack(spacing: theme.metrics.card.infoHeaderGap) {
        NumberBadge(card.id)
        Text(card.place).font(type.caption).foregroundStyle(theme.text.supporting.color)
        Spacer(minLength: 0)
        Text(card.extra).font(type.bodyStrong)
      }
      Text(card.title).font(type.bodyMedium)
      Text(card.detail)
        .font(type.caption)
        .lineSpacing(type.captionLineSpacing)
        .foregroundStyle(theme.text.secondary.color)
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(theme.text.primary.color)
    .accessibilityElement(children: .combine)
  }
}

/// The selected prompt: where it is, what was typed, its figures, and a link
/// to the context at its last request.
private struct PromptDetailView: View {
  let detail: PromptDetail
  let onShowContext: (Int) -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    let tile = theme.metrics.tile
    VStack(alignment: .leading, spacing: theme.metrics.timeline.detailGap) {
      HStack(spacing: tile.headerGap) {
        // The selected band's chip, so the detail reads as that band's.
        Text(detail.number)
          .font(theme.type.smallStrong)
          .foregroundStyle(theme.chart.phaseInkSelected.color)
          .padding(.horizontal, tile.chipInset)
          .frame(minWidth: tile.chipHeight, minHeight: tile.chipHeight)
          .background(
            RoundedRectangle(cornerRadius: theme.metrics.timeline.bandRadius)
              .fill(theme.chart.phaseSelected.color))
        Text(detail.requests).font(theme.type.caption)
          .foregroundStyle(theme.text.secondary.color)
      }
      Text(detail.prompt)
        .font(theme.type.heading)
        .lineSpacing(theme.type.headingLineSpacing)
        .foregroundStyle(theme.text.primary.color)
        .lineLimit(tile.promptLines)
        .fixedSize(horizontal: false, vertical: true)
      FactsView(facts: detail.facts)
      Button(detail.link) { onShowContext(detail.linkRequest) }
        .buttonStyle(.borderedPush)
    }
  }
}
