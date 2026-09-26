public enum ContentClassifier {
  private static let window = 4000

  public static func classify(_ text: String) -> ContentClass {
    guard !text.isEmpty else { return .prose }

    var punctuation = 0
    var indentedLines = 0
    var lines = 1
    var previousWasNewline = false
    var length = 0
    for scalar in text.unicodeScalars {
      length += 1
      if length > window { break }
      switch scalar {
      case "{", "}", "[", "]", "\"", ":", ",":
        punctuation += 1
      case "\n":
        lines += 1
        previousWasNewline = true
        continue
      case " ", "\t":
        if previousWasNewline { indentedLines += 1 }
      default:
        break
      }
      previousWasNewline = false
    }

    if Double(punctuation) / Double(length) > 0.08 { return .json }
    if Double(indentedLines) > Double(lines) * 0.25 { return .code }
    return .prose
  }
}
