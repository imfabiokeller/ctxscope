internal import SwiftUI

/// One button per prompt over the columns it spans, the selected one dark,
/// each with its number where `PromptLabels` finds room for it. A band with no
/// room for its number says it in its tooltip; the selected one says it on
/// a chip over itself.
struct PromptBands: View {
  let prompts: [PromptRow]
  let layout: ColumnLayout
  let onSelect: (Int) -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    let metrics = theme.metrics.timeline
    let shown = prompts.filter { $0.requests.lowerBound < layout.count }
    let spans = shown.map { prompt in
      let span = layout.span(
        prompt.requests.lowerBound...min(prompt.requests.upperBound, layout.count - 1))
      return PromptLabels.Span(x: span.x, width: span.width)
    }
    let places = PromptLabels.place(
      spans, labels: shown.map { MeasuredRole.smallStrong.width(of: $0.number) },
      selected: shown.firstIndex(where: \.isSelected), total: layout.width,
      inset: metrics.bandLabelInset, chipInset: metrics.bandChipInset)
    ZStack(alignment: .topLeading) {
      ForEach(shown.indices, id: \.self) { index in
        band(shown[index], span: spans[index], labeled: places[index] == .inside)
      }
      ForEach(shown.indices, id: \.self) { index in
        if case .chip(let x, let width) = places[index] {
          chip(shown[index].number, width: width).offset(x: x)
        }
      }
    }
    .font(theme.type.smallStrong)
    .frame(width: layout.width, height: metrics.bandHeight, alignment: .topLeading)
  }

  private func band(_ prompt: PromptRow, span: PromptLabels.Span, labeled: Bool) -> some View {
    let metrics = theme.metrics.timeline
    return Button {
      onSelect(prompt.id)
    } label: {
      Text(labeled ? prompt.number : "")
        .foregroundStyle(
          (prompt.isSelected ? theme.chart.phaseInkSelected : theme.chart.phaseInk).color
        )
        .frame(width: span.width, height: metrics.bandHeight)
        .background(
          RoundedRectangle(cornerRadius: metrics.bandRadius)
            .fill((prompt.isSelected ? theme.chart.phaseSelected : theme.chart.phase).color)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .offset(x: span.x)
    .help(TimelineWords.band(prompt))
    .accessibilityLabel("Prompt \(prompt.number): \(prompt.prompt)")
    .accessibilityAddTraits(prompt.isSelected ? .isSelected : [])
  }

  /// The selected prompt's number, on a chip lower than a band so it reads
  /// as a label over the band rather than as a wider band.
  private func chip(_ number: String, width: CGFloat) -> some View {
    let side = theme.metrics.badge
    return Text(number)
      .foregroundStyle(theme.chart.phaseInkSelected.color)
      .frame(width: width, height: side)
      .background(Capsule().fill(theme.chart.phaseSelected.color))
      .frame(height: theme.metrics.timeline.bandHeight)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}
