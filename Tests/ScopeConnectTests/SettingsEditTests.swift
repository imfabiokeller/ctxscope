import Foundation
import Testing

@testable import ScopeConnect

@Suite("settings edits")
struct SettingsEditTests {
  static let port: UInt16 = 45871

  private func connected(_ text: String?) throws -> Data {
    try SettingsEdit.connected(text.map { Data($0.utf8) }, port: Self.port)
  }

  private func roundTrip(_ text: String) throws {
    let original = Data(text.utf8)
    let on = try SettingsEdit.connected(original, port: Self.port)
    #expect(on != original)
    let off = try SettingsEdit.disconnected(on, original: original)
    #expect(off == original, "undo was not byte identical")
  }

  @Test("no file at all gives a settings file of our own")
  func noFile() throws {
    let written = try SettingsEdit.connected(nil, port: Self.port)
    let root = try JSONSpan.parse(written)
    #expect(root["hooks"]?.members?.map(\.name) == HookWiring.allEvents)
    #expect(try SettingsEdit.installedPorts(written).count == HookWiring.events.count)
    #expect(String(decoding: written, as: UTF8.self).hasSuffix("}\n"))
  }

  @Test("an empty file is the same as no file")
  func emptyFile() throws {
    #expect(try connected("") == (try SettingsEdit.connected(nil, port: Self.port)))
    #expect(try connected("\n  \n") == (try SettingsEdit.connected(nil, port: Self.port)))
  }

  @Test("a file with settings but no hooks keeps every key it had")
  func noHooks() throws {
    let text = """
      {
        "model": "opus",
        "permissions": {
          "allow": ["Bash(git *)"]
        }
      }

      """
    let on = try connected(text)
    let root = try JSONSpan.parse(on)
    #expect(root.members?.map(\.name) == ["model", "permissions", "hooks"])
    #expect(String(decoding: on, as: UTF8.self).contains("\"Bash(git *)\""))
    #expect(try SettingsEdit.installedPorts(on).count == HookWiring.events.count)
    try roundTrip(text)
  }

  @Test("hooks on other events are left alone")
  func unrelatedHooks() throws {
    let text = """
      {
        "hooks": {
          "PreToolUse": [
            {
              "matcher": "Bash",
              "hooks": [
                {
                  "type": "command",
                  "command": "/usr/local/bin/audit.sh"
                }
              ]
            }
          ]
        }
      }

      """
    let on = try connected(text)
    #expect(String(decoding: on, as: UTF8.self).contains("/usr/local/bin/audit.sh"))
    let root = try JSONSpan.parse(on)
    #expect(root["hooks"]?.members?.map(\.name) == ["PreToolUse"] + HookWiring.allEvents)
    try roundTrip(text)
  }

  @Test("hooks on the same events gain an entry rather than losing theirs")
  func sameEvents() throws {
    let text = """
      {
        "hooks": {
          "SessionEnd": [
            {
              "hooks": [
                {
                  "type": "command",
                  "command": "say done"
                }
              ]
            }
          ]
        }
      }

      """
    let on = try connected(text)
    let root = try JSONSpan.parse(on)
    #expect(root["hooks"]?["SessionEnd"]?.elements?.count == 2)
    #expect(String(decoding: on, as: UTF8.self).contains("say done"))
    try roundTrip(text)
  }

  @Test("an empty array on one of our events is appended to, not replaced")
  func emptyArray() throws {
    let text = "{\n  \"hooks\": {\n    \"SessionEnd\": []\n  }\n}\n"
    let on = try connected(text)
    #expect(try JSONSpan.parse(on)["hooks"]?["SessionEnd"]?.elements?.count == 1)
    try roundTrip(text)
  }

  @Test("connecting twice writes the same bytes")
  func idempotent() throws {
    let text = "{\n  \"model\": \"opus\"\n}\n"
    let once = try connected(text)
    let twice = try SettingsEdit.connected(once, port: Self.port)
    #expect(once == twice)
  }

  @Test("a different port rewrites rather than doubles")
  func portChange() throws {
    let text = "{\n  \"model\": \"opus\"\n}\n"
    let once = try connected(text)
    let moved = try SettingsEdit.connected(once, port: 45999)
    #expect(try SettingsEdit.installedPorts(moved).allSatisfy { $0 == 45999 })
    #expect(try SettingsEdit.installedPorts(moved).count == HookWiring.events.count)
    #expect(try SettingsEdit.disconnected(moved, original: Data(text.utf8)) == Data(text.utf8))
  }

  @Test(
    "odd formatting survives",
    arguments: [
      "{\"model\":\"opus\"}",
      "{\r\n\t\"model\": \"opus\"\r\n}\r\n",
      "{\n    \"model\": \"opus\",\n    \"env\": { \"A\": \"b\" }\n}\n",
      "{\n  \"hooks\" : {\n\n  }\n}\n",
      "{\n  \"a\": [1, 2, 3],\n  \"b\": {\"c\": [{\"d\": null}]}\n}\n",
    ])
  func oddFormatting(text: String) throws {
    try roundTrip(text)
  }

  @Test("a key ctxscope does not know is a key ctxscope does not touch")
  func unknownKeys() throws {
    let text = "{\n  \"futureSetting\": {\"deep\": [true, false, null, 1.5e3]}\n}\n"
    let on = try connected(text)
    #expect(String(decoding: on, as: UTF8.self).contains("\"deep\": [true, false, null, 1.5e3]"))
    try roundTrip(text)
  }

  @Test("a file changed between connect and disconnect loses only our entries")
  func changedInBetween() throws {
    let text = "{\n  \"model\": \"opus\"\n}\n"
    let on = try connected(text)
    let theirs = String(decoding: on, as: UTF8.self).replacingOccurrences(
      of: "\"hooks\": {\n",
      with: "\"hooks\": {\n    \"PreToolUse\": [\n      {\n        \"hooks\": []\n      }\n    ],\n"
    )
    let off = try SettingsEdit.disconnected(Data(theirs.utf8))
    let root = try JSONSpan.parse(off)
    #expect(root["hooks"]?.members?.map(\.name) == ["PreToolUse"])
    #expect(root["model"]?.text == "opus")
    #expect(try SettingsEdit.installedPorts(off).isEmpty)
  }

  @Test("our handler inside somebody else's group comes out alone")
  func mixedGroup() throws {
    let text = """
      {
        "hooks": {
          "SessionEnd": [
            {
              "hooks": [
                {
                  "type": "command",
                  "command": "say done"
                },
                {
                  "type": "http",
                  "url": "http://127.0.0.1:45871/ctxscope/hook",
                  "timeout": 1
                }
              ]
            }
          ]
        }
      }

      """
    let off = try SettingsEdit.disconnected(Data(text.utf8))
    #expect(String(decoding: off, as: UTF8.self).contains("say done"))
    #expect(try SettingsEdit.installedPorts(off).isEmpty)
    #expect(try JSONSpan.parse(off)["hooks"]?["SessionEnd"]?.elements?.count == 1)
  }

  @Test("undo leaves the layout intact when ours came first")
  func removedFromTheFront() throws {
    // ctxscope wrote into an empty array, and somebody appended after it.
    let text = """
      {
        "hooks": {
          "SessionEnd": [
            {
              "hooks": [
                {
                  "type": "http",
                  "url": "http://127.0.0.1:45871/ctxscope/hook",
                  "timeout": 1
                }
              ]
            },
            {
              "hooks": [
                {
                  "type": "command",
                  "command": "say done"
                }
              ]
            }
          ]
        }
      }

      """
    let off = String(decoding: try SettingsEdit.disconnected(Data(text.utf8)), as: UTF8.self)
    #expect(off.contains("say done"))
    #expect(try SettingsEdit.installedPorts(Data(off.utf8)).isEmpty)
    #expect(off.contains("\"SessionEnd\": [\n      {\n        \"hooks\": ["))
    #expect(!off.contains("[{"))
    #expect(!off.contains("[\n      ,"))
  }

  @Test("a file with nothing of ours in it is not touched at all")
  func nothingOfOurs() throws {
    let text = "{\n  \"hooks\": {\n    \"PreToolUse\": []\n  }\n}\n"
    #expect(try SettingsEdit.disconnected(Data(text.utf8)) == Data(text.utf8))
  }

  @Test(
    "a malformed file is refused and named",
    arguments: [
      "{\n  \"model\": \"opus\",\n}\n",
      "// a comment\n{}\n",
      "{\n  \"model\": 'opus'\n}\n",
      "[1, 2]",
      "{\"hooks\": []}",
    ])
  func malformed(text: String) throws {
    #expect(throws: (any Error).self) {
      try SettingsEdit.connected(Data(text.utf8), port: Self.port)
    }
  }

  @Test("the message about a malformed file says where to look")
  func malformedMessage() throws {
    let text = "{\n  \"a\": 1,\n  \"b\": @\n}\n"
    do {
      _ = try SettingsEdit.connected(Data(text.utf8), port: Self.port)
      Issue.record("a broken file was accepted")
    } catch let invalid as JSONSpan.Invalid {
      #expect(invalid.description == "a value was expected on line 3")
    }
  }
}
