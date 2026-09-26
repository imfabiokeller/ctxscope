public import SwiftUI

// Measured glyph widths of the system font; a test holds them to it.
public struct MeasuredRole: Sendable, Hashable {
  let size: CGFloat
  let weight: Font.Weight
  let digit: CGFloat
  let dash: CGFloat
  let comma: CGFloat

  public static let smallStrong = MeasuredRole(
    size: 11, weight: .semibold, digit: 7.2823, dash: 6.7874, comma: 3.6839)
  public static let badge = MeasuredRole(
    size: 10, weight: .semibold, digit: 6.6789, dash: 6.2290, comma: 3.4076)

  var font: Font { Font.system(size: size, weight: weight).monospacedDigit() }

  public func width(of text: String) -> CGFloat {
    text.reduce(0) { sum, character in
      switch character {
      case "\u{2013}": sum + dash
      case ",": sum + comma
      default: sum + digit
      }
    }.rounded(.up)
  }
}
