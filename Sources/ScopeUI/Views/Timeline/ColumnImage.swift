internal import CoreGraphics
internal import Foundation
internal import ScopeCore

/// The timeline's columns, every block a slice, drawn into one image at the
/// display's pixel size.
///
/// A session of a few hundred requests over a few thousand blocks is hundreds
/// of thousands of rectangles, so they are drawn once per change of the lane,
/// the size, the theme or the selected prompt, off the main actor, and never
/// per frame. What moves with the pointer is drawn over the image.
enum ColumnImage {
  /// Everything that changes the picture. Two equal keys draw the same pixels.
  struct Key: Hashable, Sendable {
    let chart: Int
    let width: Int
    let height: Int
    let scale: CGFloat
    let theme: Int
    let highlighted: ClosedRange<Int>?
  }

  /// Draws the columns. The image is the plot's size in pixels, with the
  /// columns standing on its bottom edge.
  ///
  /// Every edge is on a whole pixel, so two neighbouring slices share an
  /// edge and never a blended one. The
  /// columns outside the selected prompt are drawn in one transparency layer
  /// at the dimmed opacity, which fades each column as a whole, separators
  /// included.
  static func make(
    chart: TimelineChart, layout: ColumnLayout, key: Key, theme: Theme,
    metrics: Metrics.Timeline
  ) -> CGImage? {
    guard key.width > 0, key.height > 0, chart.scale > 0,
      let context = CGContext(
        data: nil, width: key.width, height: key.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.setShouldAntialias(false)
    let painter = Painter(
      chart: chart, layout: layout, scale: key.scale,
      perToken: Double(key.height) / Double(chart.scale),
      colors: Dictionary(
        uniqueKeysWithValues: Kind.allCases.map { ($0, theme.color(of: $0).cgColor) }),
      untyped: theme.color(of: nil).cgColor,
      gap: theme.chart.blockGap.cgColor,
      gapPixels: max(1, (metrics.blockGap * key.scale).rounded()),
      metrics: metrics)
    let dimmed = chart.columns.indices.filter { !chart.isHighlighted($0) }
    if !dimmed.isEmpty {
      context.setAlpha(theme.chart.dimmedOpacity)
      context.beginTransparencyLayer(auxiliaryInfo: nil)
      context.setAlpha(1)
      for column in dimmed { painter.draw(column, into: context) }
      context.endTransparencyLayer()
      context.setAlpha(1)
    }
    for column in chart.columns.indices where chart.isHighlighted(column) {
      painter.draw(column, into: context)
    }
    return context.makeImage()
  }

  /// Draws one column's slices, bottom up.
  private struct Painter {
    let chart: TimelineChart
    let layout: ColumnLayout
    let scale: CGFloat
    let perToken: Double
    let colors: [Kind: CGColor]
    let untyped: CGColor
    let gap: CGColor
    let gapPixels: CGFloat
    let metrics: Metrics.Timeline

    /// The slices first, then a rule on each edge between two blocks both
    /// tall enough to be told apart by it.
    func draw(_ index: Int, into context: CGContext) {
      let left = (layout.x(index) * scale).rounded()
      let right = max(left + 1, ((layout.x(index) + layout.columnWidth) * scale).rounded())
      var bottom = 0.0
      var below: Double?
      var rules: [CGRect] = []
      for slice in chart.columns[index].slices {
        let top = (Double(slice.end) * perToken).rounded()
        guard top > bottom else { continue }
        let kind = chart.blocks[Int(slice.block)].kind
        context.setFillColor(kind.flatMap { colors[$0] } ?? untyped)
        context.fill(CGRect(x: left, y: bottom, width: right - left, height: top - bottom))
        if let below, metrics.separates(below: below, above: top - bottom) {
          rules.append(CGRect(x: left, y: bottom, width: right - left, height: gapPixels))
        }
        below = top - bottom
        bottom = top
      }
      context.setFillColor(gap)
      context.fill(rules)
    }
  }
}
