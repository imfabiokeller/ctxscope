public import SwiftUI

public struct Typography: Sendable, Hashable {
  public static let standard = Typography()

  public let figure = sans(26, .semibold)
  public let figureTracking: CGFloat = -0.3
  public let figureUnit = sans(15, .regular)
  public let popoverFigure = sans(30, .semibold)
  public let popoverFigureTracking: CGFloat = -0.4
  public let popoverFigureNote = sans(14, .regular)

  public let title = sans(17, .semibold)
  public let titleLineSpacing = leading(17, 1.3)
  public let heading = sans(15, .semibold)
  public let headingLineSpacing = leading(15, 1.35)

  public let body = sans(13, .regular)
  public let bodyMedium = sans(13, .medium)
  public let bodyStrong = sans(13, .semibold)

  public let caption = sans(12, .regular)
  public let captionLineSpacing = leading(12, 1.4)
  public let captionMedium = sans(12, .medium)
  public let captionStrong = sans(12, .semibold)

  public let smallMedium = sans(11, .medium)
  public let small = sans(11, .regular)
  public let smallStrong = MeasuredRole.smallStrong.font

  public let axis = sans(10, .regular)
  public let badge = MeasuredRole.badge.font

  public let code = mono(11.5)
  public let codeLineSpacing = leading(11.5, 1.55)
  public let codeLarge = mono(13)

  // Ascent and descent each rounded to a point: SwiftUI rounds the sum up, a point taller.
  public let lines = Lines()

  public struct Lines: Sendable, Hashable {
    public let figure: CGFloat = 35.5
    public let heading: CGFloat = 18
    public let note: CGFloat = 16
    public let body: CGFloat = 15
    public let caption: CGFloat = 14
    public let small: CGFloat = 13
    // 13 point at 1.45 is 18.85, held to 18.5.
    public let prose: CGFloat = 18.5
  }

  private static func sans(_ size: CGFloat, _ weight: Font.Weight) -> Font {
    Font.system(size: size, weight: weight).monospacedDigit()
  }

  private static func mono(_ size: CGFloat) -> Font {
    Font.system(size: size, weight: .regular, design: .monospaced)
  }

  // SwiftUI adds line spacing to the drawn line rather than setting its height.
  private static func leading(_ size: CGFloat, _ lineHeight: CGFloat) -> CGFloat {
    max(0, size * lineHeight - drawnLine(size))
  }

  // Measured with a hosting view: SwiftUI draws whole points, not the font's 1.19 ratio.
  private static func drawnLine(_ size: CGFloat) -> CGFloat {
    switch size {
    case 11.5: 14
    case 12: 15
    case 13: 16
    case 15: 19
    case 17: 20
    default: (size * 1.19).rounded(.up)
    }
  }

  public var captionExcess: CGFloat { Self.drawnLine(12) - lines.caption }
}
