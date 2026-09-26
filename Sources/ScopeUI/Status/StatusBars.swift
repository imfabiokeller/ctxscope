public import SwiftUI

/// The ink is passed in: as a template image only its alpha matters.
public struct StatusBars: View {
  let face: StatusFace
  let ink: ThemeColor
  let scale: CGFloat

  public init(face: StatusFace, ink: ThemeColor, scale: CGFloat) {
    self.face = face
    self.ink = ink
    self.scale = scale
  }

  public static let dimmedOpacity = 0.45

  public var body: some View {
    let face = face
    let scale = scale
    let ink = ink.opacity(face.isDimmed ? Self.dimmedOpacity : 1).color
    Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
      switch face.style {
      case .filled:
        for bar in StatusGlyph.filled(scale: scale) {
          context.fill(
            Path(roundedRect: bar, cornerRadius: StatusGlyph.cornerRadius), with: .color(ink))
        }
      case .outlined:
        for bar in StatusGlyph.bars {
          context.stroke(
            Path(roundedRect: bar, cornerRadius: StatusGlyph.cornerRadius), with: .color(ink),
            lineWidth: StatusGlyph.stroke)
        }
      }
    }
    .frame(width: StatusGlyph.size.width, height: StatusGlyph.size.height)
    .accessibilityHidden(true)
  }
}
