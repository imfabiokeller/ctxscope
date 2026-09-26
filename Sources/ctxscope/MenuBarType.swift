import AppKit

/// What the menu bar's number is drawn with.
///
/// The menu bar's type and its ink belong to the system, not to a theme: the
/// status item has to sit on the same baseline as every other item and invert
/// with the bar. Nothing here is a literal. The font is the system's own at
/// the system's size, which is the menu bar's, and the ink is the system's
/// own label color.
enum MenuBarType {
  /// The number beside the mark. Tabular digits, so it does not shift as the
  /// size changes.
  static var number: NSFont {
    NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
  }

  /// How the number is drawn: the menu bar's own ink, which the system
  /// inverts with the bar.
  static var numberAttributes: [NSAttributedString.Key: Any] {
    [.font: number, .foregroundColor: NSColor.labelColor]
  }

  /// The context size beside the mark, "143k", or nothing at all when there
  /// is no live session to count.
  ///
  /// Room for three digits, always. Tabular digits keep a number the same
  /// width as it changes, but not as it gains a digit, and every item to the
  /// left of ours moves when it does: the item measured 67, then 60, then 67
  /// points as its number crossed a digit.
  static func number(_ text: String?) -> NSAttributedString {
    guard let text else { return NSAttributedString(string: "", attributes: numberAttributes) }
    let digits = text.count { $0.isNumber }
    let room = String(repeating: figureSpace, count: max(0, reservedDigits - digits))
    return NSAttributedString(string: " " + room + text, attributes: numberAttributes)
  }

  /// How many digits the item keeps room for.
  static let reservedDigits = 3

  /// A space exactly as wide as a digit, which is what tabular figures make
  /// of it.
  static let figureSpace = "\u{2007}"
}
