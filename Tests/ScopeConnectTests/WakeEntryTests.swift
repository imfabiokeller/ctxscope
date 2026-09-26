import Foundation
import Testing

@testable import ScopeConnect

/// `SessionStart` takes `command` and `mcp_tool` hooks only, so the wake entry is a command.
@Suite("the entry that starts ctxscope")
struct WakeEntryTests {
  static let port: UInt16 = 45871

  @Test("the session start entry runs a command, because a URL cannot start us")
  func wakeEntry() throws {
    let on = try SettingsEdit.connected(nil, port: Self.port)
    let group = try #require(
      JSONSpan.parse(on)["hooks"]?[HookWiring.wakeEvent]?.elements?.first)
    #expect(group["matcher"]?.text == "startup|resume|clear|fork")
    // A compaction fires SessionStart inside a running session; waking there would undo the
    // power control.
    #expect(group["matcher"]?.text?.contains("compact") == false)
    let handler = try #require(group["hooks"]?.elements?.first)
    #expect(handler["type"]?.text == "command")
    #expect(handler["command"]?.text == "open -g ctxscope://wake --args --woken || true")
    #expect(handler["async"]?.flag == true)
    #expect(handler["timeout"] != nil)
    #expect(try SettingsEdit.installedPorts(on).count == HookWiring.events.count)
    #expect(try SettingsEdit.installedEvents(on) == Set(HookWiring.allEvents))
  }

  @Test("the command is the tag, so a hand written port change still comes out")
  func wakeIsFoundByItsCommand() throws {
    let text = """
      {
        "hooks": {
          "SessionStart": [
            {
              "matcher": "startup",
              "hooks": [{"type": "command", "command": "open -g ctxscope://wake"}]
            }
          ]
        }
      }

      """
    #expect(try SettingsEdit.installedEvents(Data(text.utf8)) == ["SessionStart"])
    let off = try SettingsEdit.disconnected(Data(text.utf8))
    #expect(try SettingsEdit.installedEvents(off).isEmpty)
    #expect(!String(decoding: off, as: UTF8.self).contains("ctxscope://wake"))
  }

  @Test("an older wake command is stale, not connected")
  func staleWakeCommand() throws {
    let old = """
      {
        "hooks": {
          "SessionStart": [
            {
              "matcher": "startup|resume|clear|fork",
              "hooks": [
                {"type": "command", "command": "open -g ctxscope://wake || true"}
              ]
            }
          ]
        }
      }

      """
    let data = Data(old.utf8)
    #expect(try SettingsEdit.hasStaleWake(data))
    #expect(try !SettingsEdit.hasStaleWake(SettingsEdit.connected(nil, port: Self.port)))

    let fixed = try SettingsEdit.connected(data, port: Self.port)
    #expect(try !SettingsEdit.hasStaleWake(fixed))
    let text = String(decoding: fixed, as: UTF8.self)
    #expect(text.contains(HookWiring.wakeCommand))
    #expect(!text.contains("\"open -g ctxscope://wake || true\""))
    #expect(
      try #require(JSONSpan.parse(fixed)["hooks"]?[HookWiring.wakeEvent]?.elements).count == 1)

    #expect(try SettingsEdit.installedEvents(SettingsEdit.disconnected(data)).isEmpty)
  }

  @Test("an older ctxscope's seven entries become two")
  func sevenBecomeTwo() throws {
    let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    // The file an older ctxscope wrote: six HTTP events plus the wake entry.
    var text = "{\n  \"model\": \"opus\",\n  \"hooks\": {\n"
    for event in [
      "UserPromptSubmit", "Stop", "SubagentStart", "SubagentStop", "PostModelSwitch", "SessionEnd",
    ] {
      text += "    \"\(event)\": [\n      {\n        \"hooks\": [\n          {\n"
      text += "            \"type\": \"http\",\n"
      text += "            \"url\": \"\(HookWiring.url(port: Self.port))\",\n"
      text += "            \"timeout\": 1\n          }\n        ]\n      }\n    ],\n"
    }
    text += "    \"SessionStart\": [\n      {\n"
    text += "        \"matcher\": \"\(HookWiring.wakeMatcher)\",\n"
    text += "        \"hooks\": [\n          {\n            \"type\": \"command\",\n"
    text += "            \"command\": \"\(HookWiring.wakeCommand)\",\n"
    text += "            \"async\": true,\n            \"timeout\": 5\n"
    text += "          }\n        ]\n      }\n    ]\n  }\n}\n"
    let old = Data(text.utf8)
    #expect(try SettingsEdit.installedEvents(old).count == 7)

    let now = try SettingsEdit.connected(old, port: Self.port)
    #expect(try SettingsEdit.installedEvents(now) == Set(HookWiring.allEvents))
    #expect(try SettingsEdit.installedPorts(now).count == HookWiring.events.count)
    let written = String(decoding: now, as: UTF8.self)
    for gone in ["UserPromptSubmit", "Stop", "SubagentStart", "SubagentStop", "PostModelSwitch"] {
      #expect(!written.contains(gone), "\(gone) is still in the file")
    }
    #expect(written.contains("\"model\": \"opus\""))
    #expect(written.contains(HookWiring.wakeCommand))

    #expect(try SettingsEdit.disconnected(now, original: original) == original)
  }

  @Test("somebody else's command hook on session start is theirs")
  func foreignCommandHook() throws {
    let text = """
      {
        "hooks": {
          "SessionStart": [
            {
              "hooks": [{"type": "command", "command": "say hello"}]
            }
          ]
        }
      }

      """
    let original = Data(text.utf8)
    #expect(try SettingsEdit.installedEvents(original).isEmpty)
    let on = try SettingsEdit.connected(original, port: Self.port)
    #expect(try JSONSpan.parse(on)["hooks"]?["SessionStart"]?.elements?.count == 2)
    #expect(String(decoding: on, as: UTF8.self).contains("say hello"))
    #expect(try SettingsEdit.disconnected(on, original: original) == original)
  }

  @Test("status reports entries from an older ctxscope")
  func retired() throws {
    var text = "{\n  \"hooks\": {\n"
    for event in ["UserPromptSubmit", "Stop", "SessionEnd"] {
      text += "    \"\(event)\": [{\"hooks\": [{\"type\": \"http\", "
      text += "\"url\": \"http://127.0.0.1:45871/ctxscope/hook\"}]}],\n"
    }
    text += "    \"SessionStart\": [{\"hooks\": [{\"type\": \"command\", "
    text += "\"command\": \"\(HookWiring.wakeCommand)\"}]}]\n  }\n}\n"
    let home = ClaudeHome(root: URL(fileURLWithPath: "/tmp/ctxscope-tests"))
    let files = MemoryFiles([home.settings.path: Data(text.utf8)])
    let status = try ConnectService(home: home, files: files).status()
    #expect(status.isConnected)
    #expect(status.retired == ["Stop", "UserPromptSubmit"])
    #expect(status.isPartial)
    #expect(status.needsReconnect(listening: 45871))
  }
}
