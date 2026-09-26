internal import ScopeCore
internal import SwiftUI

/// Blocks on a scale of tokens, one slice each, in their kind's color with a
/// rule after every slice wide enough to carry one, and an outline around a
/// span. The strip and the magnifier's lens are both this.
///
/// One path per kind, so a strip of a few thousand blocks is seven fills and
/// not a few thousand. Equatable, so a pointer moving over it redraws the
/// magnifier and not the strip.
struct StripBar: View, Equatable {
  let slices: ArraySlice<StripSlice>
  /// The tokens at the leading and the trailing edge.
  let window: Range<Double>
  /// The span outlined, in tokens.
  let outlined: Range<Int>?
  let cornerRadius: CGFloat
  @Environment(\.theme) private var theme

  nonisolated static func == (lhs: StripBar, rhs: StripBar) -> Bool {
    lhs.window == rhs.window && lhs.outlined == rhs.outlined
      && lhs.cornerRadius == rhs.cornerRadius && lhs.slices == rhs.slices
  }

  var body: some View {
    let strip = theme.metrics.strip
    let hairline = theme.metrics.hairline
    Canvas { context, size in
      let span = max(1, window.upperBound - window.lowerBound)
      let perToken = size.width / span
      func x(_ token: Int) -> CGFloat { (Double(token) - window.lowerBound) * perToken }
      var fills: [Kind: Path] = [:]
      var rules = Path()
      for slice in slices {
        let left = x(slice.start)
        let right = x(slice.end)
        guard right > left else { continue }
        let ruled = right - left >= strip.minimumGapped
        if let kind = slice.kind {
          fills[kind, default: Path()].addRect(
            CGRect(x: left, y: 0, width: right - left - (ruled ? hairline : 0), height: size.height)
          )
        }
        if ruled {
          rules.addRect(CGRect(x: right - hairline, y: 0, width: hairline, height: size.height))
        }
      }
      for kind in Kind.allCases {
        guard let path = fills[kind] else { continue }
        let color = theme.color(of: kind)
        context.fill(path, with: .color(color.color))
      }
      context.fill(rules, with: .color(theme.chart.blockGap.color))
      if let outlined {
        let left = x(outlined.lowerBound)
        let width = max(x(outlined.upperBound) - left, strip.selectionMinWidth)
        let inset = strip.selectionStroke / 2
        let box = CGRect(x: left, y: 0, width: width, height: size.height)
          .insetBy(dx: inset, dy: inset)
        context.stroke(
          Path(roundedRect: box, cornerRadius: strip.selectionRadius - inset),
          with: .color(theme.chart.marker.color), lineWidth: strip.selectionStroke)
      }
    }
    .background(theme.chart.track.color)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
  }
}
