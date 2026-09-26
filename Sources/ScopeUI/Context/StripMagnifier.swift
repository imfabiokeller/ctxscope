internal import ScopeCore
internal import SwiftUI

/// What is under the pointer on the strip, enlarged: the blocks around it on
/// a lens of their own, then one row each with its kind, name and size, the
/// hovered one marked. A block of 30 tokens between two of 12k is a sliver on
/// the strip and a row here. The timeline's magnifier in the strip's form:
/// the same box, the same rows.
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

  /// The tokens the lens spans: from the first block shown to the last.
  private func lens(_ range: Range<Int>) -> Range<Double> {
    guard let first = range.first, let last = range.last else { return 0..<1 }
    return Double(strip.slices[first].start)..<Double(max(strip.slices[last].end, 1))
  }
}
