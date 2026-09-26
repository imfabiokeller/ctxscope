public import CoreGraphics

public enum StatusGlyph {
  public enum State: Sendable, Equatable, CaseIterable {
    case live
    case cacheBreak
    case idle
  }

  public struct Part: Sendable, Equatable {
    public let rect: CGRect
    public let cornerRadius: CGFloat
    public let alpha: Double
  }

  public static let size = CGSize(width: 16, height: 16)
  public static let track = CGRect(x: 1, y: 5, width: 12, height: 6)
  public static let trackAlpha = 0.3
  public static let idleOpacity = 0.35
  public static let cursorWidth: CGFloat = 1.5
  public static let slices: [(left: CGFloat, right: CGFloat)] = [
    (1, 3.5), (4, 6.5), (7, 11), (11.5, 13),
  ]

  static let steps = 2 * track.width
  static let sliceGap: CGFloat = 0.5
  static let dot: CGFloat = 3.5

  static func step(_ fill: Double) -> CGFloat {
    (min(max(fill, 0), 1) * steps).rounded()
  }

  public static func snapped(_ fill: Double) -> Double {
    step(fill) / steps
  }

  public static func end(fill: Double) -> CGFloat {
    track.minX + step(fill) / 2
  }

  public static func opacity(_ state: State) -> Double {
    state == .idle ? idleOpacity : 1
  }

  public static func parts(fill: Double, state: State) -> [Part] {
    let end = end(fill: fill)
    var parts = [Part(rect: track, cornerRadius: 1, alpha: trackAlpha)]
    for slice in slices {
      let right = min(slice.right, end - sliceGap)
      guard right - slice.left >= sliceGap else { continue }
      parts.append(
        Part(
          rect: CGRect(
            x: slice.left, y: track.minY, width: right - slice.left, height: track.height),
          cornerRadius: 0.5, alpha: 1))
    }
    return parts + cursor(at: min(end, track.maxX), state: state)
  }

  static func cursor(at x: CGFloat, state: State) -> [Part] {
    let bar = { (top: CGFloat, bottom: CGFloat) in
      Part(
        rect: CGRect(x: x, y: top, width: cursorWidth, height: bottom - top),
        cornerRadius: cursorWidth / 2, alpha: 1)
    }
    switch state {
    case .live:
      let center = x + cursorWidth / 2
      let cap = CGRect(x: center - dot / 2, y: 1, width: dot, height: dot)
      return [bar(3.5, 14), Part(rect: cap, cornerRadius: dot / 2, alpha: 1)]
    case .cacheBreak:
      return [bar(1, 4), bar(12, 15)]
    case .idle:
      return [bar(2, 14)]
    }
  }
}
