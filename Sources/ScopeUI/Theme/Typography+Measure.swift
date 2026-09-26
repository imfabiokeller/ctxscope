public import SwiftUI

/// A role whose one-line numbers a layout has to know the width of before
/// it draws: the numbers over the timeline, which are shown only where they
/// fit.
///
/// Every digit of a tabular role is one width, and these numbers are
/// digits, an en dash and a thousands comma, so a number's width is the sum
/// of theirs. The widths are measured, the way `Typography`'s drawn lines
/// are, and a test holds them to the system font's own.
public struct MeasuredRole: Sendable, Hashable {
  let size: CGFloat
  let weight: Font.Weight
  let digit: CGFloat
  let dash: CGFloat
  let comma: CGFloat

  /// A prompt's number over the timeline: `Typography.smallStrong`.
  public static let smallStrong = MeasuredRole(
    size: 11, weight: .semibold, digit: 7.2823, dash: 6.7874, comma: 3.6839)
  /// A cache break's number: `Typography.badge`.
  public static let badge = MeasuredRole(
    size: 10, weight: .semibold, digit: 6.6789, dash: 6.2290, comma: 3.4076)

  var font: Font { Font.system(size: size, weight: weight).monospacedDigit() }

  /// The width of a number set in this role, rounded up to the point.
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
