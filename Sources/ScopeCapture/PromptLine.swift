public import ScopeCore

/// The first line of what the person typed, shortened, for a task's row.
///
/// It is transcript text. It is read back out of the file when asked for, the
/// way a block's text is, and handed to the window only: nothing here
/// keeps it, and no recording, log or report may carry it.
public enum PromptLine {
  /// Characters a line is cut to, ellipsis included.
  public static let limit = 80

  /// The first line that has anything on it, with runs of white space made
  /// one space and cut at a word where one is near. Nil for a text with
  /// nothing on any line.
  ///
  /// With `markup`, the tags the harness wraps a slash command or a
  /// notification in are taken out: "<command-message>next</command-message>"
  /// reads "next", and a line of tags alone reads as its first tag's name.
  public static func first(of text: String, limit: Int = limit, markup: Bool = true) -> String? {
    guard let found = text.split(whereSeparator: \.isNewline).first(where: { !isBlank($0) })
    else { return nil }
    let line = markup ? Markup.strip(found) : String(found)
    let words = line.split(whereSeparator: \.isWhitespace)
    let joined = words.joined(separator: " ")
    guard joined.count > limit else { return joined }
    let cut = joined.prefix(max(1, limit - 1))
    // Cut at the last space when it keeps most of the line, so the line
    // does not end half way through a word.
    if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2
    {
      return cut[..<space] + "\u{2026}"
    }
    return cut + "\u{2026}"
  }

  /// The first line of every typed prompt of a lane, by the prompt's block.
  /// `content` reads one block's text back, and is the same call the
  /// sidebar's text box uses.
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
