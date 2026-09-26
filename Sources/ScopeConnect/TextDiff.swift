package import Foundation

/// The exact lines a write would change, for a person to read before it
/// happens. Every settings write shows its diff first.
///
/// The common prefix and suffix are taken off first and the rest goes through
/// the standard library's own difference, which is linear in the edit. A table
/// over every pair of lines is what a settings file of a few thousand lines
/// used to cost minutes and gigabytes.
package enum TextDiff {
  /// How many unchanged lines are shown around a change.
  package static let context = 2
  /// How many lines are shown at all. A diff nobody can read is not worth the
  /// memory, and what ctxscope writes is under a hundred.
  package static let maxLines = 400

  package struct Line: Sendable, Equatable {
    package enum Mark: String, Sendable {
      case added = "+"
      case removed = "-"
      case kept = " "
      case skipped = "."
    }
    package let mark: Mark
    package let text: String
  }

  /// A diff of two files, as lines. Empty when nothing changes.
  package static func lines(from old: Data, to new: Data) -> [Line] {
    let before = SourceText.lines(of: old).map { $0.trimmingCharacters(in: .newlines) }
    let after = SourceText.lines(of: new).map { $0.trimmingCharacters(in: .newlines) }
    guard before != after else { return [] }
    return capped(trimmed(merge(before, after)))
  }

  /// The same, as text. One block, no header: the panel and the terminal both
  /// show it as it is.
  package static func text(from old: Data, to new: Data) -> String {
    lines(from: old, to: new).map { $0.mark.rawValue + " " + $0.text }.joined(separator: "\n")
  }

  private static func merge(_ before: [String], _ after: [String]) -> [Line] {
    var head = 0
    while head < before.count, head < after.count, before[head] == after[head] { head += 1 }
    var tail = 0
    while tail < before.count - head, tail < after.count - head,
      before[before.count - 1 - tail] == after[after.count - 1 - tail]
    {
      tail += 1
    }
    let middleBefore = Array(before[head..<(before.count - tail)])
    let middleAfter = Array(after[head..<(after.count - tail)])
    return before[0..<head].map { Line(mark: .kept, text: $0) }
      + changes(middleBefore, middleAfter)
      + before[(before.count - tail)...].map { Line(mark: .kept, text: $0) }
  }

  /// The edit between two runs of lines, in the order a reader walks them.
  private static func changes(_ before: [String], _ after: [String]) -> [Line] {
    var removed: Set<Int> = []
    var inserted: [Int: String] = [:]
    for change in after.difference(from: before) {
      switch change {
      case .remove(let offset, _, _): removed.insert(offset)
      case .insert(let offset, let element, _): inserted[offset] = element
      }
    }
    var result: [Line] = []
    var left = 0
    var right = 0
    while left < before.count || right < after.count {
      if left < before.count, removed.contains(left) {
        result.append(Line(mark: .removed, text: before[left]))
        left += 1
        continue
      }
      if let element = inserted[right] {
        result.append(Line(mark: .added, text: element))
        right += 1
        continue
      }
      guard left < before.count, right < after.count else { break }
      result.append(Line(mark: .kept, text: before[left]))
      left += 1
      right += 1
    }
    return result
  }

  /// Keeps the changed lines and a little around them, and says how many lines
  /// it left out rather than leaving a gap the reader has to guess at.
  private static func trimmed(_ lines: [Line]) -> [Line] {
    var keep = [Bool](repeating: false, count: lines.count)
    for (slot, line) in lines.enumerated() where line.mark != .kept {
      for near in max(0, slot - context)...min(lines.count - 1, slot + context) {
        keep[near] = true
      }
    }
    var result: [Line] = []
    var skipped = 0
    for (slot, line) in lines.enumerated() {
      guard keep[slot] else {
        skipped += 1
        continue
      }
      if skipped > 0 {
        result.append(Line(mark: .skipped, text: "\(skipped) unchanged lines"))
        skipped = 0
      }
      result.append(line)
    }
    if skipped > 0 { result.append(Line(mark: .skipped, text: "\(skipped) unchanged lines")) }
    return result
  }

  /// A diff nobody could read is cut off, and says how much it cut.
  private static func capped(_ lines: [Line]) -> [Line] {
    guard lines.count > maxLines else { return lines }
    return Array(lines.prefix(maxLines))
      + [Line(mark: .skipped, text: "\(lines.count - maxLines) more lines")]
  }
}
