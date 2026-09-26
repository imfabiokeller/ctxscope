package import Foundation

package enum TextDiff {
  package static let context = 2
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

  package static func lines(from old: Data, to new: Data) -> [Line] {
    let before = SourceText.lines(of: old).map { $0.trimmingCharacters(in: .newlines) }
    let after = SourceText.lines(of: new).map { $0.trimmingCharacters(in: .newlines) }
    guard before != after else { return [] }
    return capped(trimmed(merge(before, after)))
  }

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

  private static func capped(_ lines: [Line]) -> [Line] {
    guard lines.count > maxLines else { return lines }
    return Array(lines.prefix(maxLines))
      + [Line(mark: .skipped, text: "\(lines.count - maxLines) more lines")]
  }
}
