import Foundation

@testable import ScopeUI

/// WCAG contrast, in one place, so every claim about a color being legible is
/// the same arithmetic.
///
/// The formula is the one the guideline gives: relative luminance from sRGB
/// with its transfer function undone, and the ratio of the lighter to the
/// darker with 0.05 added to both.
enum Contrast {
  static func ratio(_ one: ThemeColor, on other: ThemeColor) -> Double {
    let first = luminance(one)
    let second = luminance(other)
    return (max(first, second) + 0.05) / (min(first, second) + 0.05)
  }

  static func luminance(_ color: ThemeColor) -> Double {
    0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
  }

  private static func linear(_ value: Double) -> Double {
    value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }

  /// A color written the way a theme file writes it. Test-only, and the same
  /// parser the themes go through.
  static func color(_ text: String) -> ThemeColor {
    ThemeColor(text) ?? ThemeColor(red: 0, green: 0, blue: 0)
  }

  /// What a step has to hold as text on the window.
  static let text = 4.5
}
