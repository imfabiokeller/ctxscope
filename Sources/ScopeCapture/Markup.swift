internal import Foundation

enum Markup {
  static func strip(_ line: Substring) -> String {
    var text = ""
    var first: Substring?
    var rest = heading(line)
    while let open = rest.firstIndex(of: "<") {
      text += rest[..<open]
      guard let (name, end) = tag(in: rest[open...]) else {
        text += "<"
        rest = rest[rest.index(after: open)...]
        continue
      }
      if first == nil { first = name }
      rest = rest[end...]
    }
    text += rest
    if text.allSatisfy(\.isWhitespace), let first {
      return first.replacingOccurrences(of: "-", with: " ")
        .replacingOccurrences(of: "_", with: " ")
    }
    return text
  }

  private static func heading(_ line: Substring) -> Substring {
    let trimmed = line.drop { $0.isWhitespace }
    let marks = trimmed.prefix { $0 == "#" }
    guard (1...6).contains(marks.count), trimmed.dropFirst(marks.count).first == " " else {
      return line
    }
    return trimmed.dropFirst(marks.count + 1)
  }

  private static func tag(in text: Substring) -> (Substring, Substring.Index)? {
    var start = text.index(after: text.startIndex)
    if start < text.endIndex, text[start] == "/" { start = text.index(after: start) }
    guard start < text.endIndex, text[start].isLetter,
      let close = text[start...].firstIndex(of: ">")
    else { return nil }
    let inside = text[start..<close]
    let name = inside.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    let after = inside.dropFirst(name.count)
    guard after.isEmpty || after.first?.isWhitespace == true else { return nil }
    return (name, text.index(after: close))
  }
}
