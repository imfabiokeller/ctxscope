import Foundation

@testable import ScopeUI

/// WCAG 2 relative luminance and contrast ratio.
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

  static func color(_ text: String) -> ThemeColor {
    ThemeColor(text) ?? ThemeColor(red: 0, green: 0, blue: 0)
  }

  /// WCAG AA for normal text.
  static let text = 4.5
}
