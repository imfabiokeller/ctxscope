public import SwiftUI

/// The few line drawings the window uses: the chevrons, the search glass and
/// the three dots of a "More" button.
///
/// Drawn rather than taken from SF Symbols, because these strokes are thinner
/// and these chevrons flatter than any symbol weight, and a control that is a
/// point off beside a native one reads as wrong. Each is written in the
/// coordinates of its own icon box and scaled to the frame it is given, so
/// the size is the caller's and the shape is always the same.
public struct Glyph: Shape {
  public enum Kind: Sendable {
    case chevronDown
    case chevronLeft
    case chevronRight
    case magnifier
    case ellipsis
  }

  public let kind: Kind

  public init(_ kind: Kind) {
    self.kind = kind
  }

  public func path(in rect: CGRect) -> Path {
    let box = Self.box(of: kind)
    let scale = min(rect.width, rect.height) / box
    let point = { (x: CGFloat, y: CGFloat) in
      CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
    }
    var path = Path()
    switch kind {
    case .chevronDown:
      path.addLines([point(2, 3.5), point(5, 6.5), point(8, 3.5)])
    case .chevronLeft:
      path.addLines([point(7.5, 2.5), point(4, 6), point(7.5, 9.5)])
    case .chevronRight:
      path.addLines([point(4.5, 2.5), point(8, 6), point(4.5, 9.5)])
    case .magnifier:
      path.addEllipse(in: circle(point(5, 5), radius: 3.5 * scale))
      path.addLines([point(8, 8), point(10.5, 10.5)])
    case .ellipsis:
      for x in [2.5, 6, 9.5] {
        path.addEllipse(in: circle(point(x, 6), radius: 1.1 * scale))
      }
    }
    return path
  }

  /// Whether the glyph is filled rather than stroked.
  public var isFilled: Bool { kind == .ellipsis }

  /// The side of the icon box the glyph is drawn in.
  private static func box(of kind: Kind) -> CGFloat {
    kind == .chevronDown ? 10 : 12
  }

  private func circle(_ center: CGPoint, radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
  }
}

/// A glyph at a size, stroked or filled as its shape asks, in the
/// current foreground style.
public struct GlyphView: View {
  private let glyph: Glyph
  private let side: CGFloat
  /// Ignored for a filled glyph.
  private let stroke: CGFloat

  public init(_ kind: Glyph.Kind, side: CGFloat, stroke: CGFloat = 0) {
    glyph = Glyph(kind)
    self.side = side
    self.stroke = stroke
  }

  public var body: some View {
    Group {
      if glyph.isFilled {
        glyph.fill()
      } else {
        glyph.stroke(style: StrokeStyle(lineWidth: stroke))
      }
    }
    .frame(width: side, height: side)
    .accessibilityHidden(true)
  }
}
