public import SwiftUI

/// The mark, drawn. One drawing, which the application turns into a menu bar
/// image and the snapshot tool turns into a picture.
///
/// The ink is passed in rather than taken from a theme: the application
/// draws it as a template image, whose color the system replaces with
/// whatever the bar needs, so only its alpha matters there.
public struct StatusBars: View {
  let face: StatusFace
  let ink: ThemeColor
  /// The scale the filled bars are snapped to, so nothing is drawn across a
  /// pixel boundary on the display it will be shown on.
  let scale: CGFloat

  public init(face: StatusFace, ink: ThemeColor, scale: CGFloat) {
    self.face = face
    self.ink = ink
    self.scale = scale
  }

  /// An idle session is the same mark, quieter.
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
