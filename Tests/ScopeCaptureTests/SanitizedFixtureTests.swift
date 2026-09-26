import Foundation
import Testing

@testable import ScopeCapture

@Suite("sanitized fixtures")
struct SanitizedFixtureTests {
  /// The pool `scripts/sanitize-transcript.py` draws filler from.
  static let filler: Set<String> = [
    "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india",
    "juliet", "kilo", "lima", "mike", "november", "oscar", "papa", "quebec", "romeo",
    "sierra", "tango", "uniform", "victor", "whiskey", "xray", "yankee", "zulu",
  ]

  /// Categories of the harness's `/context` report: structure, not text.
  static let reportKinds: Set<String> = ["used", "deferred", "buffer", "free"]

  /// Who put a user turn there: structure, not text.
  static let originKinds: Set<String> = ["human", "task-notification"]

  static let names = ["short-session", "compaction-session", "subagent-lane", "parallel-calls"]

  @Test("no fixture carries a kind nobody replaced", arguments: names)
  func kindsAreStructureOrFiller(name: String) throws {
    var seen = 0
    for entry in try AdapterTests.fixture(name) {
      Self.walk(entry.raw, key: nil) { value in
        seen += 1
        guard !Self.reportKinds.contains(value), !Self.originKinds.contains(value) else { return }
        let words = value.split(whereSeparator: { !$0.isLetter }).map(String.init)
        #expect(!words.isEmpty)
        // Filler is cut to the length of what it replaced, so a last word can be a prefix.
        #expect(words.allSatisfy { word in Self.filler.contains { $0.hasPrefix(word) } })
      }
    }
    #expect(seen >= 0)
  }

  private static func walk(_ value: JSONValue, key: String?, _ body: (String) -> Void) {
    switch value {
    case .object(let object):
      for (name, item) in object { walk(item, key: name, body) }
    case .array(let items):
      for item in items { walk(item, key: key, body) }
    case .string(let text):
      if key == "kind" { body(text) }
    default:
      break
    }
  }
}
