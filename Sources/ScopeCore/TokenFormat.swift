public enum TokenFormat {
  public static func tokens(_ value: Int) -> String {
    let magnitude = abs(value)
    let sign = value < 0 ? "-" : ""
    // Thresholds are where the rounded number crosses, so 999950 reads 1.00M, never 1000.0k.
    if magnitude >= 999_500 {
      return sign + decimal(Double(magnitude) / 1_000_000, places: 2) + "M"
    }
    if magnitude >= 9950 { return sign + decimal(Double(magnitude) / 1000, places: 1) + "k" }
    if magnitude >= 1000 { return sign + decimal(Double(magnitude) / 1000, places: 2) + "k" }
    return sign + String(magnitude)
  }

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

  public static func count(_ value: Int) -> String {
    String(value)
  }

  public static func plural(_ value: Int, _ noun: String) -> String {
    "\(count(value)) \(noun)\(value == 1 ? "" : "s")"
  }

  public static func tokens(_ tokens: Tokens) -> String {
    "\(self.tokens(tokens.value)) \(tokens.grade.rawValue)"
  }

  public static func signedPercent(_ share: Double) -> String {
    guard share.isFinite else { return "n/a" }
    let value = Int((share * 100).rounded())
    return (value > 0 ? "+" : "") + String(value) + "%"
  }

  public static func percent(_ share: Double) -> String {
    guard share.isFinite else { return "n/a" }
    return String(Int((share * 100).rounded())) + "%"
  }

  public static func finePercent(_ share: Double) -> String {
    guard share.isFinite else { return "n/a" }
    return decimal(share * 100, places: 1) + "%"
  }

  public static func ratio(_ value: Double, places: Int = 2) -> String {
    value.isFinite ? decimal(value, places: places) : "n/a"
  }

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
    // String(Double) prints 1.0 for a whole value; pad to the requested places.
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
  public static func dollars(_ value: Double) -> String {
    guard value.isFinite else { return "n/a" }
    let magnitude = abs(value)
    let places = magnitude >= 0.1 || magnitude == 0 ? 2 : (magnitude >= 0.01 ? 3 : 4)
    return (value < 0 ? "-$" : "$") + decimal(magnitude, places: places)
  }

  public static func cents(_ value: Double) -> String {
    guard value.isFinite else { return "n/a" }
    return (value < 0 ? "-$" : "$") + decimal(abs(value), places: 2)
  }

  public static func short(_ value: Int) -> String {
    let magnitude = abs(value)
    guard magnitude >= 1000, magnitude < 999_500 else { return tokens(value) }
    return (value < 0 ? "-" : "") + decimal(Double(magnitude) / 1000, places: 1) + "k"
  }

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
