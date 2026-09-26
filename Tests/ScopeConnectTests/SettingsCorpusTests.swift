import Foundation
import Testing

@testable import ScopeConnect

/// A corpus of settings files, every one of them made up here.
///
/// Every shape of settings file anybody has thought of, so the next one is
/// added to a list. Nothing in it comes from a real machine: the shapes are
/// what matters, never the contents.
@Suite("a corpus of settings files")
struct SettingsCorpusTests {
  static let port: UInt16 = 45871

  /// Files the harness reads. Connecting and disconnecting has to give the
  /// same bytes back.
  static let valid: [(String, String)] = [
    ("empty object", "{}"),
    ("empty object with a newline", "{}\n"),
    ("one key", "{\n  \"model\": \"opus\"\n}\n"),
    ("compact", "{\"model\":\"opus\"}"),
    (
      "four spaces", "{\n    \"model\": \"opus\",\n    \"env\": {\n        \"A\": \"b\"\n    }\n}\n"
    ),
    ("tabs", "{\n\t\"model\": \"opus\",\n\t\"env\": {\n\t\t\"A\": \"b\"\n\t}\n}\n"),
    ("carriage returns", "{\r\n  \"model\": \"opus\"\r\n}\r\n"),
    ("no trailing newline", "{\n  \"model\": \"opus\"\n}"),
    ("blank lines between keys", "{\n\n  \"model\": \"opus\",\n\n  \"a\": 1\n\n}\n"),
    ("spaces before the colon", "{\n  \"model\" : \"opus\"\n}\n"),
    (
      "permissions",
      """
      {
        "permissions": {
          "allow": ["Bash(git *)", "Read(./src)"],
          "deny": []
        }
      }

      """
    ),
    (
      "env and statusline",
      """
      {
        "env": {"A": "b", "C": "d"},
        "statusLine": {"type": "command", "command": "/x/y.sh"}
      }

      """
    ),
    ("unknown future keys", "{\n  \"futureSetting\": {\"deep\": [true, false, null, 1.5e3]}\n}\n"),
    (
      "numbers of every shape",
      "{\n  \"a\": [0, -0, 1.5, -2.25e-3, 1E+10, 12345678901234567890]\n}\n"
    ),
    ("escapes in a string", #"{"a": "x\ty\\z\"q\/r\b\f\n"}"#),
    ("a unicode escape", #"{"a": "\u00e9\u0041"}"#),
    ("a surrogate pair", #"{"a": "\uD83D\uDE00"}"#),
    ("characters outside ASCII", "{\n  \"a\": \"grün, 日本語\"\n}\n"),
    ("an empty hooks object", "{\n  \"hooks\": {}\n}\n"),
    ("an empty hooks object with whitespace", "{\n  \"hooks\" : {\n\n  }\n}\n"),
    (
      "a hook on another event",
      """
      {
        "hooks": {
          "PreToolUse": [
            {
              "matcher": "Bash",
              "hooks": [{"type": "command", "command": "/x/audit.sh"}]
            }
          ]
        }
      }

      """
    ),
    (
      "a hook on one of ours",
      """
      {
        "hooks": {
          "Stop": [
            {
              "hooks": [{"type": "command", "command": "say done"}]
            }
          ]
        }
      }

      """
    ),
    ("an empty array on one of ours", "{\n  \"hooks\": {\n    \"Stop\": []\n  }\n}\n"),
    (
      "several matcher groups",
      """
      {
        "hooks": {
          "PreToolUse": [
            {"matcher": "Bash", "hooks": [{"type": "command", "command": "a"}]},
            {"matcher": "Edit", "hooks": [{"type": "command", "command": "b"}]}
          ],
          "SessionEnd": [
            {"matcher": "clear", "hooks": [{"type": "command", "command": "c"}]}
          ]
        }
      }

      """
    ),
    (
      "nesting a settings file might really have",
      """
      {
        "a": {"b": {"c": {"d": {"e": {"f": [1, [2, [3, [4]]]]}}}}}
      }

      """
    ),
    (
      "a long file",
      "{\n" + (0..<500).map { "  \"k\($0)\": \($0)," }.joined(separator: "\n")
        + "\n  \"last\": true\n}\n"
    ),
  ]

  /// Files ctxscope will not touch. Every one of them has to come back with
  /// the same bytes and a refusal somebody can read.
  static let refused: [(String, String)] = [
    ("a comment", "// mine\n{\n  \"model\": \"opus\"\n}\n"),
    ("a block comment", "{\n  /* mine */ \"model\": \"opus\"\n}\n"),
    ("a trailing comma", "{\n  \"model\": \"opus\",\n}\n"),
    ("single quotes", "{\n  'model': 'opus'\n}\n"),
    ("an unquoted key", "{\n  model: \"opus\"\n}\n"),
    ("a byte order mark", "\u{FEFF}{\"model\": \"opus\"}"),
    ("an array at the root", "[1, 2, 3]"),
    ("a string at the root", "\"opus\""),
    ("a number at the root", "42"),
    ("nothing at all", ""),
    ("only whitespace", "  \n\t\n "),
    ("an unterminated string", "{\n  \"model\": \"opus\n}\n"),
    ("an unterminated object", "{\n  \"model\": \"opus\"\n"),
    ("two documents", "{\"a\": 1}\n{\"b\": 2}\n"),
    ("a key written twice", "{\n  \"hooks\": {},\n  \"hooks\": {\"Stop\": []}\n}\n"),
    ("a key written twice deeper down", "{\n  \"a\": {\"b\": 1, \"b\": 2}\n}\n"),
    ("a number the harness rejects", "{\n  \"a\": 1-2e+.\n}\n"),
    ("a plus in front of a number", "{\n  \"a\": +1\n}\n"),
    (
      "nesting past the cap",
      String(repeating: "[", count: 5_000)
        + String(repeating: "]", count: 5_000)
    ),
    // JSON.parse takes a lone surrogate and JSONSerialization does not, so
    // ctxscope leaves the file alone. The span parser reads it without
    // trapping either way, which is what finding 4 was about.
    ("a lone surrogate", #"{"a": "\uD800\u0041"}"#),
    ("a surrogate pair in the wrong order", #"{"a": "\uDC00\uD800"}"#),
  ]

  /// Files that are valid JSON but not a settings file ctxscope can work on.
  static let wrongShape: [(String, String)] = [
    ("hooks is null", "{\n  \"hooks\": null\n}\n"),
    ("hooks is an array", "{\n  \"hooks\": []\n}\n"),
    ("hooks is a string", "{\n  \"hooks\": \"none\"\n}\n"),
    ("an event that is not an array", "{\n  \"hooks\": {\"SessionEnd\": {}}\n}\n"),
    ("an event that is a number", "{\n  \"hooks\": {\"SessionEnd\": 1}\n}\n"),
  ]

  @Test("a file the harness reads comes back byte for byte", arguments: valid)
  func roundTrip(name: String, text: String) throws {
    let original = Data(text.utf8)
    #expect(WriteGuard.isWellFormed(original), "\(name) was refused")
    let on = try SettingsEdit.connected(original, port: Self.port)
    #expect(on != original, "\(name) gained nothing")
    #expect(WriteGuard.isWellFormed(on), "\(name) became unreadable")
    #expect(try SettingsEdit.installedPorts(on).count == HookWiring.events.count, "\(name)")
    #expect(try SettingsEdit.disconnected(on, original: original) == original, "\(name)")
  }

  @Test("a file the harness would read differently is left alone", arguments: refused)
  func leftAlone(name: String, text: String) {
    let original = Data(text.utf8)
    #expect(!WriteGuard.isWellFormed(original), "\(name) was accepted")
  }

  @Test("a file with a hooks block ctxscope cannot edit is refused", arguments: wrongShape)
  func wrongShapeIsRefused(name: String, text: String) {
    let original = Data(text.utf8)
    #expect(throws: (any Error).self, "\(name) was edited") {
      try SettingsEdit.connected(original, port: Self.port)
    }
  }

  @Test("bytes that are not text are left alone")
  func notText() {
    var withNul = Data("{\"a\": \"x".utf8)
    withNul.append(0)
    withNul.append(contentsOf: Data("\"}".utf8))
    #expect(!WriteGuard.isWellFormed(withNul))
    #expect(
      !WriteGuard.isWellFormed(Data([0x7B, 0x22, 0x61, 0x22, 0x3A, 0x22, 0xFF, 0x22, 0x7D])))
  }

  @Test("nothing in the corpus ever kills the process")
  func nothingTraps() {
    for (_, text) in Self.valid + Self.refused + Self.wrongShape {
      let data = Data(text.utf8)
      _ = try? JSONSpan.parse(data)
      _ = WriteGuard.isWellFormed(data)
      _ = try? SettingsEdit.connected(data, port: Self.port)
      _ = try? SettingsEdit.disconnected(data)
      _ = try? SettingsEdit.installedPorts(data)
    }
  }

  /// Files ctxscope has already written to. Connecting again settles them
  /// rather than doubling them, and undo takes only what ctxscope put there.
  @Test(
    "a file ctxscope has already written to",
    arguments: [
      ("the same port", Self.port), ("another port", UInt16(45999)),
    ])
  func alreadyConnected(name: String, port: UInt16) throws {
    let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    let on = try SettingsEdit.connected(original, port: port)
    let again = try SettingsEdit.connected(on, port: Self.port)
    #expect(
      try SettingsEdit.installedPorts(again)
        == [UInt16](
          repeating: Self.port, count: HookWiring.events.count), "\(name)")
    #expect(try SettingsEdit.disconnected(again, original: original) == original, "\(name)")
  }

  @Test("a file with only some of our entries is filled in, not doubled")
  func partiallyConnected() throws {
    let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    var half = String(
      decoding: try SettingsEdit.connected(original, port: Self.port), as: UTF8.self)
    // Take one event back out by hand, the way a half finished write would.
    for event in [HookWiring.events[0]] {
      let start = half.range(of: "    \"\(event)\": [")
      guard let start else { continue }
      let end =
        half.range(of: "    ],\n", range: start.upperBound..<half.endIndex)
        ?? half.range(of: "    ]\n", range: start.upperBound..<half.endIndex)
      guard let end else { continue }
      half.removeSubrange(start.lowerBound..<end.upperBound)
    }
    let data = Data(half.utf8)
    #expect(try SettingsEdit.installedEvents(data).count == HookWiring.allEvents.count - 1)
    let filled = try SettingsEdit.connected(data, port: Self.port)
    #expect(try SettingsEdit.installedPorts(filled).count == HookWiring.events.count)
    #expect(try SettingsEdit.installedEvents(filled) == Set(HookWiring.allEvents))
    #expect(try SettingsEdit.disconnected(filled, original: original) == original)
  }

  @Test("somebody else's http hook on our path is theirs")
  func foreignHTTPHook() throws {
    // `localhost` is the same machine by another name, and ctxscope writes
    // 127.0.0.1. An entry it did not write is one it does not touch.
    let text = """
      {
        "hooks": {
          "Stop": [
            {
              "hooks": [
                {"type": "http", "url": "http://localhost:45871/ctxscope/hook"}
              ]
            }
          ]
        }
      }

      """
    let original = Data(text.utf8)
    #expect(try SettingsEdit.installedPorts(original).isEmpty)
    #expect(try SettingsEdit.disconnected(original) == original)
    let on = try SettingsEdit.connected(original, port: Self.port)
    #expect(String(decoding: on, as: UTF8.self).contains("http://localhost:45871/ctxscope/hook"))
    #expect(try SettingsEdit.disconnected(on, original: original) == original)
  }
}
