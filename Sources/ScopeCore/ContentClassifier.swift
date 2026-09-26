/// Picks the content class the estimator fits a rate for. One source of
/// truth, used by every adapter, so two harnesses classify the same text the
/// same way.
public enum ContentClassifier {
  /// Only the head of a long block is inspected: the class of 400 KB of
  /// shell output is decided in its first lines like everything else.
  private static let window = 4000

  public static func classify(_ text: String) -> ContentClass {
    guard !text.isEmpty else { return .prose }

    var punctuation = 0
    var indentedLines = 0
    var lines = 1
    var previousWasNewline = false
    var length = 0
    // Only the head is inspected, and it is taken by walking scalars rather
    // than by copying a prefix out: this runs on every block of every
    // request, including 400 KB ones.
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
