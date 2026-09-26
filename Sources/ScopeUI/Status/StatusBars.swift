public import SwiftUI

/// The ink is passed in: as a template image only its alpha matters.
public struct StatusBars: View {
  let face: StatusFace
  let ink: ThemeColor

  public init(face: StatusFace, ink: ThemeColor) {
    self.face = face
    self.ink = ink
  }

  public var body: some View {
    let parts = StatusGlyph.parts(fill: face.fill, state: face.state)
    let opacity = StatusGlyph.opacity(face.state)
    let ink = ink
    Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
      // One layer, so where parts overlap the idle opacity dims them once, as in the kit.
      context.opacity = opacity
      context.drawLayer { layer in
        for part in parts {
          layer.fill(
            Path(roundedRect: part.rect, cornerRadius: part.cornerRadius),
            with: .color(ink.opacity(part.alpha).color))
        }
      }
    }
    .frame(width: StatusGlyph.size.width, height: StatusGlyph.size.height)
    .accessibilityHidden(true)
  }
}
