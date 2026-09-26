internal import ScopeCore
public import SwiftUI

/// Where the pointer is over the strip: the slice under it, and how far
/// along the strip it is.
public struct StripHover: Equatable, Sendable {
  public let index: Int
  public let x: CGFloat

  public init(index: Int, x: CGFloat) {
    self.index = index
    self.x = x
  }
}

/// "Context in reading order": the two marks, the strip of every block at the
/// window's scale, and the legend. Hovering names the blocks under the
/// pointer in a magnifier; a click selects the block.
struct ContextStrip: View {
  let strip: StripData
  let legend: [LegendEntryData]
  let onSelect: (SegmentID) -> Void
  @State private var hover: StripHover?
  @Environment(\.theme) private var theme

  /// `hover` is where the pointer starts, for a picture of the magnifier.
  init(
    strip: StripData, legend: [LegendEntryData], hover: StripHover? = nil,
    onSelect: @escaping (SegmentID) -> Void
  ) {
    self.strip = strip
    self.legend = legend
    self.onSelect = onSelect
    _hover = State(initialValue: hover)
  }

  var body: some View {
    let metrics = theme.metrics.strip
    VStack(alignment: .leading, spacing: metrics.gap) {
      SectionHeader(strip.title, detail: Text(strip.scaleNote))
      StripMarks(strip: strip)
      GeometryReader { proxy in
        StripBar(
          slices: strip.slices[...], window: 0..<Double(strip.scale), outlined: strip.selected,
          cornerRadius: metrics.cornerRadius
        )
        .equatable()
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
          switch phase {
          case .active(let point):
            hover = index(at: point.x, width: proxy.size.width).map {
              StripHover(index: $0, x: point.x)
            }
          case .ended:
            hover = nil
          }
        }
        .onTapGesture(coordinateSpace: .local) { point in
          guard let found = index(at: point.x, width: proxy.size.width) else { return }
          onSelect(strip.slices[found].id)
        }
        .overlay(alignment: .topLeading) {
          if let hover, strip.slices.indices.contains(hover.index) {
            let magnifier = theme.metrics.magnifier
            StripMagnifier(strip: strip, index: hover.index)
              .offset(
                x: max(0, min(hover.x - magnifier.width / 2, proxy.size.width - magnifier.width)),
                y: metrics.height + metrics.magnifierOffset
              )
              .allowsHitTesting(false)
          }
        }
      }
      .frame(height: metrics.height)
      // Above the legend that follows it, so the magnifier hanging below the
      // strip covers the legend rather than the other way round.
      .zIndex(1)
      .accessibilityElement()
      .accessibilityLabel(strip.title)
      .accessibilityValue(strip.scaleNote)
      HStack(spacing: metrics.legendGap) {
        ForEach(legend) { entry in
          KindLegendItem(
            color: theme.color(of: entry.kind), name: entry.name,
            detail: entry.detail)
        }
      }
    }
  }

  private func index(at x: CGFloat, width: CGFloat) -> Int? {
    guard width > 0 else { return nil }
    return strip.slice(at: Double(x / width) * Double(strip.scale))
  }
}
