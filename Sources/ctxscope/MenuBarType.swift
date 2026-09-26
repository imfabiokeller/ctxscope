import AppKit

enum MenuBarType {
  static var number: NSFont {
    NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
  }

  static var numberAttributes: [NSAttributedString.Key: Any] {
    [.font: number, .foregroundColor: NSColor.labelColor]
  }

  static func number(_ text: String?) -> NSAttributedString {
    guard let text else { return NSAttributedString(string: "", attributes: numberAttributes) }
    let digits = text.count { $0.isNumber }
    let room = String(repeating: figureSpace, count: max(0, reservedDigits - digits))
    return NSAttributedString(string: " " + room + text, attributes: numberAttributes)
  }

  // Tabular digits hold width only within a digit count; items left of ours move when it grows.
  static let reservedDigits = 3

  static let figureSpace = "\u{2007}"
}
