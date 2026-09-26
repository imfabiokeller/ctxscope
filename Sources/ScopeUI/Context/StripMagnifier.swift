internal import ScopeCore
internal import SwiftUI

struct StripMagnifier: View {
  let strip: StripData
  let index: Int
  @Environment(\.theme) private var theme

  var body: some View {
    let magnifier = theme.metrics.magnifier
    let range = strip.neighborhood(of: index, count: magnifier.rows)
    let hovered = strip.slices[index]
    let shape = RoundedRectangle(cornerRadius: magnifier.cornerRadius)
    let shadow = theme.shadow.popover
    VStack(alignment: .leading, spacing: 0) {
      MagnifierHeader(
        title: strip.request, figures: strip.figures,
        window: MagnifierWords.window(range, of: strip.slices.count))
      StripBar(
        slices: strip.slices[range], window: lens(range),
        outlined: hovered.start..<hovered.end, cornerRadius: magnifier.columnRadius
      )
      .frame(height: theme.metrics.strip.lensHeight)
      .padding(.bottom, magnifier.subtitleGap)
      ForEach(range, id: \.self) { slot in
        let slice = strip.slices[slot]
        MagnifierRow(
          color: theme.color(of: slice.kind), label: slice.label, size: slice.size,
          isHovered: slot == index)
      }
    }
    .padding(magnifier.padding)
    .frame(width: magnifier.width, alignment: .leading)
    .background {
      shape.fill(theme.surface.popover.color)
        .shadow(color: shadow.color.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
    .overlay { shape.strokeBorder(theme.line.popover.color, lineWidth: theme.metrics.hairline) }
  }

  private func lens(_ range: Range<Int>) -> Range<Double> {
    guard let first = range.first, let last = range.last else { return 0..<1 }
    return Double(strip.slices[first].start)..<Double(max(strip.slices[last].end, 1))
  }
}
