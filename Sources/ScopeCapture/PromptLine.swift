public import ScopeCore

// Transcript text: hand it to the window only, never to a recording, log or report.
public enum PromptLine {
  public static let limit = 80

  public static func first(of text: String, limit: Int = limit, markup: Bool = true) -> String? {
    guard let found = text.split(whereSeparator: \.isNewline).first(where: { !isBlank($0) })
    else { return nil }
    let line = markup ? Markup.strip(found) : String(found)
    let words = line.split(whereSeparator: \.isWhitespace)
    let joined = words.joined(separator: " ")
    guard joined.count > limit else { return joined }
    let cut = joined.prefix(max(1, limit - 1))
    if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2
    {
      return cut[..<space] + "\u{2026}"
    }
    return cut + "\u{2026}"
  }

  public static func lines(
    of lane: Lane, limit: Int = limit, content: (SegmentID) -> SegmentContent?
  ) -> [SegmentID: String] {
    var lines: [SegmentID: String] = [:]
    for prompt in lane.prompts {
      guard let text = content(prompt)?.text, let line = first(of: text, limit: limit) else {
        continue
      }
      lines[prompt] = line
    }
    return lines
  }

  private static func isBlank(_ line: Substring) -> Bool {
    line.allSatisfy(\.isWhitespace)
  }
}
