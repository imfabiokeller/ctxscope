package import Foundation

package struct TextSplice: Sendable, Equatable {
  package let range: Range<Int>
  package let text: String

  package init(range: Range<Int>, text: String) {
    self.range = range
    self.text = text
  }

  package static func insert(at offset: Int, _ text: String) -> TextSplice {
    TextSplice(range: offset..<offset, text: text)
  }

  package static func remove(_ range: Range<Int>) -> TextSplice {
    TextSplice(range: range, text: "")
  }
}

package enum SourceText {
  // Back to front, so an earlier splice never moves a later one's offsets.
  package static func apply(_ splices: [TextSplice], to data: Data) -> Data {
    var bytes = [UInt8](data)
    for splice in splices.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
      let lower = max(0, min(splice.range.lowerBound, bytes.count))
      let upper = max(lower, min(splice.range.upperBound, bytes.count))
      bytes.replaceSubrange(lower..<upper, with: [UInt8](splice.text.utf8))
    }
    return Data(bytes)
  }

  package static func lineIndent(at offset: Int, in data: Data) -> String {
    let bytes = [UInt8](data)
    let position = max(0, min(offset, bytes.count))
    var start = position
    while start > 0, bytes[start - 1] != 0x0A { start -= 1 }
    var end = start
    while end < bytes.count, bytes[end] == 0x20 || bytes[end] == 0x09 { end += 1 }
    return String(decoding: bytes[start..<min(end, position)], as: UTF8.self)
  }

  package static func indentUnit(in data: Data) -> String {
    for line in String(decoding: data, as: UTF8.self).split(
      separator: "\n", omittingEmptySubsequences: false)
    {
      let indent = line.prefix { $0 == " " || $0 == "\t" }
      if !indent.isEmpty, indent.count < line.count { return String(indent) }
    }
    return "  "
  }

  package static func lineBreak(in data: Data) -> String {
    let bytes = [UInt8](data)
    guard let feed = bytes.firstIndex(of: 0x0A) else { return "\n" }
    return feed > 0 && bytes[feed - 1] == 0x0D ? "\r\n" : "\n"
  }

  package static func lines(of data: Data) -> [String] {
    var lines: [String] = []
    var current = ""
    for character in String(decoding: data, as: UTF8.self) {
      current.append(character)
      if character == "\n" {
        lines.append(current)
        current = ""
      }
    }
    if !current.isEmpty { lines.append(current) }
    return lines
  }
}
