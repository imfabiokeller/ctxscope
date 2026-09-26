/// Turns text into a set of hashed word k-grams. One source of truth: the
/// adapter shingles content it sees, the judge only ever handles the hashes,
/// so no transcript text reaches a recording, a log, or a report.
public enum Shingler {
  /// Five words is long enough that ordinary phrases do not collide and
  /// short enough that a reused sentence fragment still matches.
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

  /// The one shingle a tool definition is judged by.
  ///
  /// A tool schema is referenced when the tool is called.
  /// Nothing in a response has to quote a schema to have followed it, so the
  /// call is the evidence, and it is carried as a shingle so the ordinary
  /// index, cutoff and share apply to it unchanged. The separator is a byte no
  /// tool name holds, so a name can never collide with real words.
  public static func toolCall(_ name: String) -> UInt64 {
    hash("tool-call\u{1}" + name)
  }

  /// Lowercased runs of letters and digits. Punctuation and whitespace are
  /// separators, so JSON and prose shingle the same way.
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

  /// Hashed k-grams of `text`, in order, duplicates kept so coverage can be
  /// measured as a share.
  public static func shingles(of text: String) -> [UInt64] {
    let words = words(text)
    guard words.count >= width else {
      return words.isEmpty ? [] : [hash(words.joined(separator: " "))]
    }
    return shingles(words)
  }

  /// At most `limit` shingles, spread evenly over the text. A 400 KB tool
  /// result does not need every k-gram for its referenced share to be within
  /// a percent, and the cap is what keeps a 1M-token window in memory.
  ///
  /// The offsets are chosen first and only those are hashed. Hashing every
  /// k-gram and then throwing away all but 400 of them was a third of the
  /// time a large session took.
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

  /// Hashes one k-gram in place, without building the joined string.
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
