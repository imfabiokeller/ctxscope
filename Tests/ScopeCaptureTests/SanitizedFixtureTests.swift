import Foundation
import Testing

@testable import ScopeCapture

/// A fixture is a real transcript with its text replaced. These are the checks
/// that say so, because a rule in the sanitizer that copies a field through is
/// invisible until somebody looks.
@Suite("sanitized fixtures")
struct SanitizedFixtureTests {
  /// The pool `scripts/sanitize-transcript.py` draws filler from.
  static let filler: Set<String> = [
    "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india",
    "juliet", "kilo", "lima", "mike", "november", "oscar", "papa", "quebec", "romeo",
    "sierra", "tango", "uniform", "victor", "whiskey", "xray", "yankee", "zulu",
  ]

  /// Words that are a category of the harness's own context report, which is
  /// structure: it says whether a category is in the context at all.
  static let reportKinds: Set<String> = ["used", "deferred", "buffer", "free"]

  /// Who put a user turn there, which is structure too: it is what tells a
  /// typed prompt from a background task's report.
  static let originKinds: Set<String> = ["human", "task-notification"]

  static let names = ["short-session", "compaction-session", "subagent-lane", "parallel-calls"]

  /// Every `kind` in a fixture is either one of the report's four words or
  /// filler. `kind` was briefly kept at any depth, which would have copied a
  /// person's own words through wherever the harness uses that field for
  /// something else.
  @Test("no fixture carries a kind nobody replaced", arguments: names)
  func kindsAreStructureOrFiller(name: String) throws {
    var seen = 0
    for entry in try AdapterTests.fixture(name) {
      Self.walk(entry.raw, key: nil) { value in
        seen += 1
        guard !Self.reportKinds.contains(value), !Self.originKinds.contains(value) else { return }
        let words = value.split(whereSeparator: { !$0.isLetter }).map(String.init)
        #expect(!words.isEmpty)
        // Filler is cut to the length of what it replaced, so the last word of
        // a run can be the start of one.
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
