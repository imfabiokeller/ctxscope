internal import SwiftUI

struct StripMarks: View {
  let strip: StripData
  @Environment(\.theme) private var theme

  var body: some View {
    let metrics = theme.metrics.strip
    let hairline = theme.metrics.hairline
    MarksLayout(
      prefix: strip.prefix.map { Double($0.at) / Double(strip.scale) },
      cache: strip.cache.map { Double($0.at) / Double(strip.scale) },
      minimumBracket: 2 * hairline, inset: metrics.markLabelInset, gap: metrics.markLabelGap,
      labelHeight: theme.type.lines.small
    ) {
      if let prefix = strip.prefix {
        bracket.layoutValue(key: MarkRole.self, value: .bracket)
        Rectangle().fill(theme.chart.bracket.color).frame(width: hairline)
          .layoutValue(key: MarkRole.self, value: .bracketEdge)
        label(prefix.label).layoutValue(key: MarkRole.self, value: .prefixLabel)
      }
      if let cache = strip.cache {
        Rectangle().fill(theme.chart.marker.color).frame(width: hairline)
          .layoutValue(key: MarkRole.self, value: .cacheLine)
        label(cache.label).layoutValue(key: MarkRole.self, value: .cacheLabel)
      }
    }
    .frame(height: metrics.markHeight)
  }

  private var bracket: some View {
    let hairline = theme.metrics.hairline
    let color = theme.chart.bracket.color
    return ZStack(alignment: .bottomLeading) {
      Rectangle().fill(color).frame(width: hairline)
      Rectangle().fill(color).frame(height: hairline)
    }
  }

  private func label(_ text: String) -> some View {
    Text(text)
      .font(theme.type.small)
      .foregroundStyle(theme.text.supporting.color)
      .lineLimit(1)
      .fixedSize()
  }
}

private enum MarkRole: LayoutValueKey {
  case none
  case bracket
  case bracketEdge
  case prefixLabel
  case cacheLine
  case cacheLabel

  static let defaultValue = MarkRole.none
}

private struct MarksLayout: Layout {
  let prefix: Double?
  let cache: Double?
  let minimumBracket: CGFloat
  let inset: CGFloat
  let gap: CGFloat
  let labelHeight: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    func find(_ role: MarkRole) -> LayoutSubview? { subviews.first { $0[MarkRole.self] == role } }
    let width = bounds.width
    let prefixEnd = prefix.map { max(CGFloat($0) * width, minimumBracket) }
    let cacheAt = self.cache.map { CGFloat($0) * width }
    let prefixLabel = find(.prefixLabel)
    let cacheLabel = find(.cacheLabel)
    let place = StripMarkLayout.place(
      width: width, prefixEnd: prefixEnd,
      prefixWidth: prefixLabel?.sizeThatFits(.unspecified).width ?? 0, cacheAt: cacheAt,
      cacheWidth: cacheLabel?.sizeThatFits(.unspecified).width ?? 0, inset: inset,
      line: find(.cacheLine)?.sizeThatFits(.unspecified).width ?? 0, gap: gap)
    if let prefixEnd, let bracket = find(.bracket) {
      bracket.place(
        at: bounds.origin, proposal: ProposedViewSize(width: prefixEnd, height: bounds.height))
    }
    if let prefixEnd, let edge = find(.bracketEdge) {
      upright(
        edge, at: prefixEnd - edge.sizeThatFits(.unspecified).width,
        under: place.crossesBracketEdge, in: bounds)
    }
    if let x = place.prefixLabel, let prefixLabel {
      prefixLabel.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY), proposal: .unspecified)
    }
    if let cacheAt, let line = find(.cacheLine) {
      upright(line, at: cacheAt, under: place.crossesCacheLine, in: bounds)
    }
    if let x = place.cacheLabel, let cacheLabel {
      cacheLabel.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY), proposal: .unspecified)
    }
  }

  private func upright(_ view: LayoutSubview, at x: CGFloat, under: Bool, in bounds: CGRect) {
    let top = under ? labelHeight : 0
    view.place(
      at: CGPoint(x: bounds.minX + x, y: bounds.minY + top),
      proposal: ProposedViewSize(width: nil, height: bounds.height - top))
  }
}
