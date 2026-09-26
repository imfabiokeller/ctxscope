/// One source of truth for how a number reaches a human, in the CLI and in
/// the UI. Tabular, short, and never without its grade.
public enum TokenFormat {
  /// 942, 1.20k, 12.4k, 1.05M.
  public static func tokens(_ value: Int) -> String {
    let magnitude = abs(value)
    let sign = value < 0 ? "-" : ""
    // The thresholds are where the rounded number crosses, not where the raw
    // one does, so 999950 reads as 1.00M and never as 1000.0k.
    if magnitude >= 999_500 {
      return sign + decimal(Double(magnitude) / 1_000_000, places: 2) + "M"
    }
    if magnitude >= 9950 { return sign + decimal(Double(magnitude) / 1000, places: 1) + "k" }
    if magnitude >= 1000 { return sign + decimal(Double(magnitude) / 1000, places: 2) + "k" }
    return sign + String(magnitude)
  }

  /// As few characters as a token count can take and still be read: 942,
  /// 9.6k, 143k, 1.2M. The menu bar item's number, where every character
  /// pushes the items to its left along.
  public static func brief(_ value: Int) -> String {
    let magnitude = abs(value)
    let sign = value < 0 ? "-" : ""
    if magnitude >= 999_500 {
      return sign + decimal(Double(magnitude) / 1_000_000, places: 1) + "M"
    }
    if magnitude >= 9950 { return sign + decimal(Double(magnitude) / 1000, places: 0) + "k" }
    if magnitude >= 1000 { return sign + decimal(Double(magnitude) / 1000, places: 1) + "k" }
    return sign + String(magnitude)
  }

  /// A round number for an axis or a window size: 120k, 200k, 1M. Decimals on
  /// a boundary nobody chose to three digits of precision are noise.
  public static func axis(_ value: Int) -> String {
    let magnitude = abs(value)
    let sign = value < 0 ? "-" : ""
    if magnitude >= 1_000_000, magnitude % 1_000_000 == 0 {
      return sign + String(magnitude / 1_000_000) + "M"
    }
    if magnitude >= 1000, magnitude % 1000 == 0 {
      return sign + String(magnitude / 1000) + "k"
    }
    return tokens(value)
  }

  /// A plain count, never localized. An axis that prints 1000 beside a footer
  /// that prints 1,020 is two conventions in one window.
  public static func count(_ value: Int) -> String {
    String(value)
  }

  /// A count and its noun, with the s only when there should be one.
  public static func plural(_ value: Int, _ noun: String) -> String {
    "\(count(value)) \(noun)\(value == 1 ? "" : "s")"
  }

  /// A token count with its provenance, the only way a number is shown.
  public static func tokens(_ tokens: Tokens) -> String {
    "\(self.tokens(tokens.value)) \(tokens.grade.rawValue)"
  }

  /// 0.07 becomes "+7%", which is how far one number is from another.
  public static func signedPercent(_ share: Double) -> String {
    guard share.isFinite else { return "n/a" }
    let value = Int((share * 100).rounded())
    return (value > 0 ? "+" : "") + String(value) + "%"
  }

  /// 0.732 becomes "73%".
  public static func percent(_ share: Double) -> String {
    guard share.isFinite else { return "n/a" }
    return String(Int((share * 100).rounded())) + "%"
  }

  /// 0.0732 becomes "7.3%", for residuals where a whole percent is too
  /// coarse.
  public static func finePercent(_ share: Double) -> String {
    guard share.isFinite else { return "n/a" }
    return decimal(share * 100, places: 1) + "%"
  }

  public static func ratio(_ value: Double, places: Int = 2) -> String {
    value.isFinite ? decimal(value, places: places) : "n/a"
  }

  /// Right-aligns in a column of `width`.
  public static func pad(_ text: String, to width: Int) -> String {
    text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
  }

  public static func padRight(_ text: String, to width: Int) -> String {
    if text.count > width {
      return String(text.prefix(max(0, width - 1))) + "\u{2026}"
    }
    return text + String(repeating: " ", count: width - text.count)
  }

  static func decimal(_ value: Double, places: Int) -> String {
    let scale = pow10(places)
    let rounded = (value * scale).rounded() / scale
    guard places > 0 else { return String(Int(rounded)) }
    var text = String(rounded)
    // Swift prints 1.0 for a whole double. Pad to the requested places so
    // columns line up.
    if let dot = text.firstIndex(of: ".") {
      let fraction = text.distance(from: text.index(after: dot), to: text.endIndex)
      if fraction < places {
        text += String(repeating: "0", count: places - fraction)
      } else if fraction > places {
        text = String(text.prefix(text.distance(from: text.startIndex, to: dot) + places + 1))
      }
    } else if places > 0 {
      text += "." + String(repeating: "0", count: places)
    }
    return text
  }

  private static func pow10(_ places: Int) -> Double {
    var value = 1.0
    for _ in 0..<max(0, places) { value *= 10 }
    return value
  }
}

extension TokenFormat {
  /// Dollars, with as many places as it takes for a small amount to say
  /// something: "$3.94" and "$0.39", "$0.058", "$0.0043". Nothing the table
  /// prices is small enough to need more.
  public static func dollars(_ value: Double) -> String {
    guard value.isFinite else { return "n/a" }
    let magnitude = abs(value)
    let places = magnitude >= 0.1 || magnitude == 0 ? 2 : (magnitude >= 0.01 ? 3 : 4)
    return (value < 0 ? "-$" : "$") + decimal(magnitude, places: places)
  }

  /// Dollars to the cent, whatever the amount: a column of costs lines up on
  /// the point and never switches to three places row by row.
  public static func cents(_ value: Double) -> String {
    guard value.isFinite else { return "n/a" }
    return (value < 0 ? "-$" : "$") + decimal(abs(value), places: 2)
  }

  /// A size the way the window writes it: one decimal from a thousand on,
  /// "3.1k", "142.6k", "1.05M". `tokens` keeps two places below 10k, which a
  /// table of sizes side by side does not need.
  public static func short(_ value: Int) -> String {
    let magnitude = abs(value)
    guard magnitude >= 1000, magnitude < 999_500 else { return tokens(value) }
    return (value < 0 ? "-" : "") + decimal(Double(magnitude) / 1000, places: 1) + "k"
  }

  /// Bytes, which are not tokens and must not be formatted as if they were.
  public static func bytes(_ value: Int) -> String {
    let magnitude = abs(value)
    if magnitude >= 1_073_741_824 {
      return decimal(Double(value) / 1_073_741_824, places: 1) + " GB"
    }
    if magnitude >= 1_048_576 { return decimal(Double(value) / 1_048_576, places: 1) + " MB" }
    if magnitude >= 1024 { return decimal(Double(value) / 1024, places: 1) + " KB" }
    return "\(value) B"
  }
}
