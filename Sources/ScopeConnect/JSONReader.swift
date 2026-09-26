internal import Foundation

// Byte by byte: every range it reports must be a byte offset a splice can use.
struct JSONReader {
  let bytes: [UInt8]
  var at = 0
  // Counted, because running out of stack crashes without an error.
  var depth = 0

  func fail(_ what: String) -> JSONSpan.Invalid {
    .unexpected(what, line: bytes[0..<min(at, bytes.count)].count { $0 == 0x0A } + 1)
  }

  mutating func skipSpace() {
    while at < bytes.count,
      bytes[at] == 0x20 || bytes[at] == 0x09 || bytes[at] == 0x0A
        || bytes[at] == 0x0D
    {
      at += 1
    }
  }

  mutating func value() throws -> JSONSpan {
    skipSpace()
    guard at < bytes.count else { throw fail("a value was expected") }
    switch bytes[at] {
    case UInt8(ascii: "{"): return try object()
    case UInt8(ascii: "["): return try array()
    case UInt8(ascii: "\""):
      let start = at
      let value = try string()
      return JSONSpan(kind: .string(value), range: start..<at)
    case UInt8(ascii: "t"): return try literal("true", .bool(true))
    case UInt8(ascii: "f"): return try literal("false", .bool(false))
    case UInt8(ascii: "n"): return try literal("null", .null)
    default: return try number()
    }
  }

  private mutating func literal(_ word: String, _ kind: JSONSpan.Kind) throws -> JSONSpan {
    let want = [UInt8](word.utf8)
    guard at + want.count <= bytes.count, Array(bytes[at..<(at + want.count)]) == want else {
      throw fail("a value was expected")
    }
    let start = at
    at += want.count
    return JSONSpan(kind: kind, range: start..<at)
  }

  private mutating func number() throws -> JSONSpan {
    let start = at
    if at < bytes.count, bytes[at] == UInt8(ascii: "-") { at += 1 }
    var digits = 0
    while at < bytes.count, isNumberByte(bytes[at]) {
      if bytes[at] >= UInt8(ascii: "0"), bytes[at] <= UInt8(ascii: "9") { digits += 1 }
      at += 1
    }
    guard digits > 0 else { throw fail("a value was expected") }
    return JSONSpan(kind: .number, range: start..<at)
  }

  private func isNumberByte(_ byte: UInt8) -> Bool {
    (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) || byte == UInt8(ascii: "+")
      || byte == UInt8(ascii: "-") || byte == UInt8(ascii: ".") || byte == UInt8(ascii: "e")
      || byte == UInt8(ascii: "E")
  }

  private mutating func deepen() throws {
    depth += 1
    guard depth <= JSONSpan.depthLimit else {
      throw fail("more than \(JSONSpan.depthLimit) levels of nesting")
    }
  }

  private mutating func object() throws -> JSONSpan {
    let start = at
    try deepen()
    defer { depth -= 1 }
    at += 1
    var members: [JSONSpan.Member] = []
    skipSpace()
    if at < bytes.count, bytes[at] == UInt8(ascii: "}") {
      at += 1
      return JSONSpan(kind: .object(members), range: start..<at)
    }
    while true {
      skipSpace()
      let nameStart = at
      guard at < bytes.count, bytes[at] == UInt8(ascii: "\"") else {
        throw fail("a key was expected")
      }
      let name = try string()
      skipSpace()
      guard at < bytes.count, bytes[at] == UInt8(ascii: ":") else {
        throw fail("a colon was expected")
      }
      at += 1
      let value = try value()
      members.append(
        JSONSpan.Member(name: name, range: nameStart..<value.range.upperBound, value: value))
      skipSpace()
      guard at < bytes.count else { throw fail("the object is not closed") }
      if bytes[at] == UInt8(ascii: ",") {
        at += 1
        continue
      }
      guard bytes[at] == UInt8(ascii: "}") else {
        throw fail("a comma or a closing brace was expected")
      }
      at += 1
      return JSONSpan(kind: .object(members), range: start..<at)
    }
  }

  private mutating func array() throws -> JSONSpan {
    let start = at
    try deepen()
    defer { depth -= 1 }
    at += 1
    var elements: [JSONSpan] = []
    skipSpace()
    if at < bytes.count, bytes[at] == UInt8(ascii: "]") {
      at += 1
      return JSONSpan(kind: .array(elements), range: start..<at)
    }
    while true {
      elements.append(try value())
      skipSpace()
      guard at < bytes.count else { throw fail("the array is not closed") }
      if bytes[at] == UInt8(ascii: ",") {
        at += 1
        continue
      }
      guard bytes[at] == UInt8(ascii: "]") else {
        throw fail("a comma or a closing bracket was expected")
      }
      at += 1
      return JSONSpan(kind: .array(elements), range: start..<at)
    }
  }

  private mutating func string() throws -> String {
    at += 1
    var out: [UInt8] = []
    while at < bytes.count {
      let byte = bytes[at]
      if byte == UInt8(ascii: "\"") {
        at += 1
        return String(decoding: out, as: UTF8.self)
      }
      if byte != UInt8(ascii: "\\") {
        out.append(byte)
        at += 1
        continue
      }
      at += 1
      guard at < bytes.count else { throw fail("the string is not closed") }
      let escape = bytes[at]
      at += 1
      switch escape {
      case UInt8(ascii: "n"): out.append(0x0A)
      case UInt8(ascii: "t"): out.append(0x09)
      case UInt8(ascii: "r"): out.append(0x0D)
      case UInt8(ascii: "b"): out.append(0x08)
      case UInt8(ascii: "f"): out.append(0x0C)
      case UInt8(ascii: "u"): out.append(contentsOf: try unicode())
      default: out.append(escape)
      }
    }
    throw fail("the string is not closed")
  }

  // A lone or misordered surrogate decodes to U+FFFD, since `JSON.parse` accepts it.
  private mutating func unicode() throws -> [UInt8] {
    let first = try hex()
    var scalar = UInt32(first)
    if first >= 0xD800, first <= 0xDBFF, at + 1 < bytes.count, bytes[at] == UInt8(ascii: "\\"),
      bytes[at + 1] == UInt8(ascii: "u")
    {
      let mark = at
      at += 2
      let second = try hex()
      if second >= 0xDC00, second <= 0xDFFF {
        scalar = 0x10000 + (UInt32(first - 0xD800) << 10) + (UInt32(second) - 0xDC00)
      } else {
        at = mark
        scalar = 0xFFFD
      }
    }
    if scalar >= 0xD800, scalar <= 0xDFFF { scalar = 0xFFFD }
    guard let value = Unicode.Scalar(scalar) else { return Array("\u{FFFD}".utf8) }
    return Array(String(Character(value)).utf8)
  }

  private mutating func hex() throws -> UInt16 {
    guard at + 4 <= bytes.count,
      let value = UInt16(String(decoding: bytes[at..<(at + 4)], as: UTF8.self), radix: 16)
    else { throw fail("a four digit escape was expected") }
    at += 4
    return value
  }
}
