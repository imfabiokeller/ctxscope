public import CoreGraphics

public enum StatusGlyph {
  public static let size = CGSize(width: 14, height: 12)
  public static let cornerRadius: CGFloat = 0.6
  public static let stroke: CGFloat = 1

  public static let bars: [CGRect] = [
    CGRect(x: 0.5, y: 7, width: 3, height: 4.5),
    CGRect(x: 5.5, y: 4, width: 3, height: 7.5),
    CGRect(x: 10.5, y: 0.5, width: 3, height: 11),
  ]

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
