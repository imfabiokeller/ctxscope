internal import Foundation
public import SwiftUI

/// One color, written the way a theme file writes it, and turned into a
/// display color in one place.
///
/// Three notations: `#RRGGBB`, `rgba(r, g, b, a)` and `oklch(L C H)`, the
/// last converted through OKLab so a color written as a lightness is that
/// lightness on screen.
public struct ThemeColor: Sendable, Hashable, Codable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public let alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  public init(from decoder: any Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    guard let parsed = ThemeColor(text) else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath, debugDescription: "not a color: \(text)"))
    }
    self = parsed
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }

  public var description: String {
    let channel = { (value: Double) in Int((value * 255).rounded()) }
    return "rgba(\(channel(red)),\(channel(green)),\(channel(blue)),\(alpha))"
  }

  public var color: Color {
    Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
  }

  /// The same color for Core Graphics, which is what the cached column image
  /// is drawn with. Views never build one themselves.
  ///
  /// sRGB, the same space SwiftUI's own colors are in. Device RGB matches it
  /// on the offscreen renders and can differ on a wide gamut display, which
  /// would put the columns in one space and everything drawn over them in
  /// another.
  public var cgColor: CGColor {
    CGColor(
      colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
      components: [red, green, blue, alpha]
    ) ?? CGColor(gray: 0, alpha: alpha)
  }

  /// The same color at a different opacity, for the one case a theme cannot
  /// name in advance: dimming the requests outside the selected prompt.
  public func opacity(_ value: Double) -> ThemeColor {
    ThemeColor(red: red, green: green, blue: blue, alpha: alpha * value)
  }

  public init?(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("#") {
      self.init(hex: trimmed.dropFirst())
      return
    }
    guard let open = trimmed.firstIndex(of: "("), trimmed.hasSuffix(")") else { return nil }
    let name = String(trimmed[trimmed.startIndex..<open])
    let numbers = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
      .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
      .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    switch name {
    case "rgba", "rgb":
      // A channel outside 0 to 255 is a typo, not a color. Clamping it would
      // turn a broken theme into a quietly wrong one.
      guard numbers.count >= 3,
        numbers[0...2].allSatisfy({ $0 >= 0 && $0 <= 255 }),
        numbers.count < 4 || (numbers[3] >= 0 && numbers[3] <= 1)
      else { return nil }
      self.init(
        red: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255,
        alpha: numbers.count > 3 ? numbers[3] : 1)
    case "oklch":
      guard numbers.count >= 3, numbers[0] >= 0, numbers[0] <= 1, numbers[1] >= 0 else {
        return nil
      }
      self.init(
        oklch: OKLCH(lightness: numbers[0], chroma: numbers[1], hue: numbers[2]),
        alpha: numbers.count > 3 ? numbers[3] : 1)
    default:
      return nil
    }
  }

  private init?(hex digits: Substring) {
    guard digits.count == 6 || digits.count == 8, let value = UInt32(digits, radix: 16) else {
      return nil
    }
    let hasAlpha = digits.count == 8
    let shift = hasAlpha ? 8 : 0
    self.init(
      red: Double((value >> (16 + shift)) & 0xff) / 255,
      green: Double((value >> (8 + shift)) & 0xff) / 255,
      blue: Double((value >> shift) & 0xff) / 255,
      alpha: hasAlpha ? Double(value & 0xff) / 255 : 1
    )
  }

  public init(oklch: OKLCH, alpha: Double = 1) {
    let (red, green, blue) = oklch.displayComponents()
    self.init(red: red, green: green, blue: blue, alpha: alpha)
  }
}

/// A color in OKLCH, and the one conversion from it to what a display shows.
public struct OKLCH: Sendable, Hashable, Codable {
  public var lightness: Double
  public var chroma: Double
  /// Degrees.
  public var hue: Double

  public init(lightness: Double, chroma: Double, hue: Double) {
    self.lightness = lightness
    self.chroma = chroma
    self.hue = hue
  }

  /// OKLCH to sRGB, by way of OKLab and linear light. Out of gamut components
  /// are clamped, which is what a display does anyway.
  public func displayComponents() -> (red: Double, green: Double, blue: Double) {
    let radians = hue * Double.pi / 180
    let a = chroma * cos(radians)
    let b = chroma * sin(radians)

    let long = pow(lightness + 0.396_337_777_4 * a + 0.215_803_757_3 * b, 3)
    let medium = pow(lightness - 0.105_561_345_8 * a - 0.063_854_172_8 * b, 3)
    let short = pow(lightness - 0.089_484_177_5 * a - 1.291_485_548_0 * b, 3)

    return (
      Self.encode(4.076_741_662_1 * long - 3.307_711_591_3 * medium + 0.230_969_929_2 * short),
      Self.encode(-1.268_438_004_6 * long + 2.609_757_401_1 * medium - 0.341_319_396_5 * short),
      Self.encode(-0.004_196_086_3 * long - 0.703_418_614_7 * medium + 1.707_614_701_0 * short)
    )
  }

  /// Linear light to sRGB, clamped to what can be shown.
  private static func encode(_ value: Double) -> Double {
    let clamped = min(1, max(0, value))
    return clamped <= 0.003_130_8
      ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
  }
}
