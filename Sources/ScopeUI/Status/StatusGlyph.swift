public import CoreGraphics

/// The mark in the menu bar: three bars rising left to right, in a box of
/// fourteen by twelve points.
///
/// Pure geometry, so it can be tested and drawn to a picture without a menu
/// bar anywhere near it. The application turns it into a template image.
public enum StatusGlyph {
  public static let size = CGSize(width: 14, height: 12)
  public static let cornerRadius: CGFloat = 0.6
  /// The outline's width, centered on the bars' edges.
  public static let stroke: CGFloat = 1

  /// The three bars, left to right, top-left origin, in points.
  public static let bars: [CGRect] = [
    CGRect(x: 0.5, y: 7, width: 3, height: 4.5),
    CGRect(x: 5.5, y: 4, width: 3, height: 7.5),
    CGRect(x: 10.5, y: 0.5, width: 3, height: 11),
  ]

  /// The bars to fill at a scale, with every edge on a whole pixel. At 2x
  /// they are `bars` exactly; at 1x their half points would fall between
  /// pixels and blur, so they are rounded to the nearest.
  public static func filled(scale: CGFloat) -> [CGRect] {
    let scale = max(1, scale)
    let snap = { (value: CGFloat) in (value * scale).rounded() / scale }
    return bars.map { bar in
      let left = snap(bar.minX)
      let top = snap(bar.minY)
      return CGRect(x: left, y: top, width: snap(bar.maxX) - left, height: snap(bar.maxY) - top)
    }
  }
}
