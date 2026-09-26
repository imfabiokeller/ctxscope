/// The judge only ever handles these hashes, so no transcript text reaches a recording.
public enum Shingler {
  /// Long enough that ordinary phrases do not collide, short enough that reused fragments match.
  public static let width = 5

  /// FNV-1a, 64 bit.
  public static func hash(_ text: some Sequence<UInt8>) -> UInt64 {
    var value: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in text {
      value ^= UInt64(byte)
      value &*= 0x0000_0100_0000_01b3
    }
    return value
  }

  public static func hash(_ text: String) -> UInt64 {
    hash(text.utf8)
  }

  /// The separator is a byte no tool name holds, so a name cannot collide with real words.
  public static func toolCall(_ name: String) -> UInt64 {
    hash("tool-call\u{1}" + name)
  }

  public static func words(_ text: String) -> [String] {
    var words: [String] = []
    var current = ""
    current.reserveCapacity(24)
    for character in text.unicodeScalars {
      if CharacterSet.isWordScalar(character) {
        current.unicodeScalars.append(character)
      } else if !current.isEmpty {
        words.append(current.lowercased())
        current = ""
      }
    }
    if !current.isEmpty { words.append(current.lowercased()) }
    return words
  }

  public static func shingles(of text: String) -> [UInt64] {
    let words = words(text)
    guard words.count >= width else {
      return words.isEmpty ? [] : [hash(words.joined(separator: " "))]
    }
    return shingles(words)
  }

  public static func sampled(of text: String, limit: Int) -> [UInt64] {
    let words = words(text)
    guard words.count >= width else {
      return words.isEmpty ? [] : [hash(words.joined(separator: " "))]
    }
    let count = words.count - width + 1
    guard limit > 0, count > limit else { return shingles(words) }
    let step = Double(count) / Double(limit)
    var result: [UInt64] = []
    result.reserveCapacity(limit)
    for index in 0..<limit {
      result.append(hash(words, at: min(count - 1, Int(Double(index) * step))))
    }
    return result
  }

  private static func hash(_ words: [String], at start: Int) -> UInt64 {
    var value: UInt64 = 0xcbf2_9ce4_8422_2325
    for offset in 0..<width {
      if offset > 0 {
        value ^= UInt64(UInt8(ascii: " "))
        value &*= 0x0000_0100_0000_01b3
      }
      for byte in words[start + offset].utf8 {
        value ^= UInt64(byte)
        value &*= 0x0000_0100_0000_01b3
      }
    }
    return value
  }

  private static func shingles(_ words: [String]) -> [UInt64] {
    guard words.count >= width else {
      return words.isEmpty ? [] : [hash(words.joined(separator: " "))]
    }
    var result: [UInt64] = []
    result.reserveCapacity(words.count - width + 1)
    for start in 0...(words.count - width) { result.append(hash(words, at: start)) }
    return result
  }

  private enum CharacterSet {
    static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
      switch scalar.value {
      case 0x30...0x39, 0x41...0x5a, 0x61...0x7a: true
      default: scalar.value > 0x7f && scalar.properties.isAlphabetic
      }
    }
  }
}
