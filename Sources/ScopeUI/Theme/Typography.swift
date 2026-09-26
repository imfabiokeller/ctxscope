public import SwiftUI

/// The type scale, by role: SF Pro for text and figures, SF
/// Mono for a block's text, tabular numerals in every role, because numbers
/// stack in almost every one of them. Views read these by name and never
/// build a font of their own, for the same reason they never build a color of
/// their own.
///
/// A role that is set with a line height or a letter spacing has
/// both beside it here, in points, so the one number lives with the font it
/// belongs to.
public struct Typography: Sendable, Hashable {
  public static let standard = Typography()

  /// A summary card's figure.
  public let figure = sans(26, .semibold)
  /// Figures are set tighter than the text around them. Tabular
  /// digits are wide, and without it a figure reads loose.
  public let figureTracking: CGFloat = -0.3
  /// The unit beside a figure: "of 200k".
  public let figureUnit = sans(15, .regular)
  /// The popover's one figure, and its note.
  public let popoverFigure = sans(30, .semibold)
  public let popoverFigureTracking: CGFloat = -0.4
  public let popoverFigureNote = sans(14, .regular)

  /// The name of the selected block, heading the sidebar.
  public let title = sans(17, .semibold)
  public let titleLineSpacing = leading(17, 1.3)
  /// A prompt heading the sidebar, and the popover's empty state.
  public let heading = sans(15, .semibold)
  public let headingLineSpacing = leading(15, 1.35)

  /// Body text: table rows, buttons, definition values.
  public let body = sans(13, .regular)
  public let bodyMedium = sans(13, .medium)
  /// Section headings and emphasized values.
  public let bodyStrong = sans(13, .semibold)

  /// Secondary text: labels, detail lines, the filter picker.
  public let caption = sans(12, .regular)
  /// A card's explanation, which wraps.
  public let captionLineSpacing = leading(12, 1.4)
  public let captionMedium = sans(12, .medium)
  public let captionStrong = sans(12, .semibold)

  /// A table's column headers, and the popover's status line.
  public let smallMedium = sans(11, .medium)
  /// Chart annotations and the popover's legend.
  public let small = sans(11, .regular)
  /// A prompt's number above the timeline.
  public let smallStrong = MeasuredRole.smallStrong.font

  /// Axis labels.
  public let axis = sans(10, .regular)
  /// The digit in a number badge.
  public let badge = MeasuredRole.badge.font

  /// A block's text.
  public let code = mono(11.5)
  public let codeLineSpacing = leading(11.5, 1.55)
  /// A command set on its own, such as `/ctxscope`.
  public let codeLarge = mono(13)

  /// The height of one line of text in each size: the font's ascent and
  /// descent each rounded to a whole point. SwiftUI rounds the sum up
  /// instead, which is a point more for most sizes, and a panel of a dozen
  /// lines ends up eight points taller than it should be.
  public let lines = Lines()

  public struct Lines: Sendable, Hashable {
    /// 30 point figures.
    public let figure: CGFloat = 35.5
    /// 15 point headings.
    public let heading: CGFloat = 18
    /// 14 point notes.
    public let note: CGFloat = 16
    /// 13 point body text, in every weight.
    public let body: CGFloat = 15
    /// 12 point captions.
    public let caption: CGFloat = 14
    /// 11 point small text.
    public let small: CGFloat = 13
    /// One line of 13 point prose at 1.45 times its size, which is 18.85
    /// points, held to 18.5.
    public let prose: CGFloat = 18.5
  }

  private static func sans(_ size: CGFloat, _ weight: Font.Weight) -> Font {
    Font.system(size: size, weight: weight).monospacedDigit()
  }

  private static func mono(_ size: CGFloat) -> Font {
    Font.system(size: size, weight: .regular, design: .monospaced)
  }

  /// SwiftUI adds line spacing to the line it draws rather than setting the
  /// whole height, so a line height written as a multiple becomes the
  /// difference between the two in points.
  private static func leading(_ size: CGFloat, _ lineHeight: CGFloat) -> CGFloat {
    max(0, size * lineHeight - drawnLine(size))
  }

  /// The line SwiftUI draws at a size, measured with a hosting view: a whole
  /// number of points, and not one ratio to the size. The font's own metrics
  /// say 1.19 times, which is 15.5 at 13 where SwiftUI draws 16, and 20.2 at
  /// 17 where it draws 20.
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

  /// How much taller SwiftUI sets a line of 12 point text than `lines` does.
  /// Text that may wrap cannot be framed to one of `lines`, so what stacks it
  /// gives this back from the space after it.
  public var captionExcess: CGFloat { Self.drawnLine(12) - lines.caption }
}
