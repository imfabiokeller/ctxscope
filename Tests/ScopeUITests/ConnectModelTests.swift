import Foundation
import ScopeConnect
import Testing

@testable import ScopeUI

/// The Connect panel's one button, against a temporary home directory. No test
/// anywhere in this package is allowed near the real `~/.claude`.
@Suite("the connect panel")
@MainActor
struct ConnectModelTests {
  private func temporary() throws -> ClaudeHome {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "ctxscope-connect-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return ClaudeHome(root: root)
  }

  @Test("the button says Connect, then Disconnect, and undo puts it back")
  func oneButton() async throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    try original.write(to: home.settings)

    let model = ConnectModel(home: home, listening: 45871)
    #expect(model.hooks == .off)
    #expect(model.skill == .none)
    #expect(model.buttonTitle == "Connect")
    #expect(model.plan?.diff().contains("\"SessionEnd\"") == true)
    // The panel's own copy is worked out off the main actor.
    for _ in 0..<200 where model.diff.isEmpty { await Task.yield() }
    #expect(model.diff.contains("\"SessionEnd\""))
    #expect(model.backupNote == "A copy of the settings file will be kept beside it.")

    model.act()
    #expect(model.hooks == .on(port: 45871))
    #expect(model.skill == .ours)
    #expect(model.buttonTitle == "Disconnect")
    #expect(model.done == "Written.")
    #expect(model.backupNote == "A copy of the settings file is kept beside it.")

    // The one button is the whole toggle: there is no second way to undo.
    model.act()
    #expect(model.hooks == .off)
    #expect(model.skill == .none)
    // Connecting again would keep a copy, so the panel says it would.
    #expect(model.backupNote == "A copy of the settings file will be kept beside it.")
    #expect(try Data(contentsOf: home.settings) == original)
  }

  @Test("a skill somebody wrote themselves is named and left alone")
  func editedSkill() throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    try FileManager.default.createDirectory(
      at: home.skillFolder, withIntermediateDirectories: true)
    let mine = Data("---\nname: mine\n---\n".utf8)
    try mine.write(to: home.skill)
    let model = ConnectModel(home: home, listening: 45871)
    #expect(model.skill == .edited)
    model.act()
    #expect(try Data(contentsOf: home.skill) == mine)
  }

  @Test("a port the app is not listening on is said out loud")
  func unreachable() throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    ConnectModel(home: home, listening: 45871).act()

    let moved = ConnectModel(home: home, listening: nil)
    #expect(moved.hooks == .unreachable(port: 45871))
    #expect(moved.hooks.text == "Connected, ctxscope not on port 45871")
    // With no listener of its own the panel leaves the written port alone.
    #expect(moved.buttonTitle == "Disconnect")
    #expect(moved.needsReconnect)
    #expect(moved.hint == "ctxscope has no port. Open it again.")

    // A listener that took another port says which one, and connecting again
    // is what points the hooks at it.
    let elsewhere = ConnectModel(home: home, listening: 45873)
    #expect(elsewhere.hooks == .unreachable(port: 45871))
    #expect(
      elsewhere.hint
        == "ctxscope is listening on port 45873. Connect again to point the hooks at it.")
    #expect(elsewhere.buttonTitle == "Connect")
    elsewhere.act()
    #expect(elsewhere.hooks == .on(port: 45873))
    #expect(elsewhere.hint == nil)
    // The note the menu bar shows is worked out from the same rule, so it goes
    // away as soon as the hooks have been connected again.
    #expect(!elsewhere.needsReconnect)
    #expect(!ConnectModel(home: home, listening: 45873).needsReconnect)
    #expect(ConnectModel(home: home, listening: 45871).needsReconnect)
  }

  @Test("a file that changed while the panel sat open is not written over")
  func stalePlan() throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    try original.write(to: home.settings)
    let model = ConnectModel(home: home, listening: 45871)

    // Claude Code writes an allow rule while the panel is open.
    let moved = Data("{\n  \"model\": \"opus\",\n  \"permissions\": {}\n}\n".utf8)
    try moved.write(to: home.settings)

    model.act()
    #expect(try Data(contentsOf: home.settings) == moved)
    #expect(model.done?.hasPrefix("The settings file changed.") == true)
    #expect(model.hooks == .off)
    #expect(model.plan?.basis == moved)

    // The second click writes, and what arrived in between survives.
    model.act()
    #expect(model.hooks == .on(port: 45871))
    let after = String(decoding: try Data(contentsOf: home.settings), as: UTF8.self)
    #expect(after.contains("\"permissions\": {}"))
    model.act()
    #expect(try Data(contentsOf: home.settings) == moved)
  }

  @Test("a malformed settings file is said and nothing is offered")
  func malformed() throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    try Data("{\n  \"model\": \"opus\",\n}\n".utf8).write(to: home.settings)
    let model = ConnectModel(home: home, listening: 45871)
    #expect(model.plan == nil)
    // The line number is back: it is what a person needs to fix the file.
    #expect(
      model.failure
        == "the settings file is not JSON: a key was expected on line 3, "
        + "so ctxscope left it alone")
    // A file ctxscope will not touch has no diff to show.
    #expect(model.diff.isEmpty)
    model.act()
    #expect(try Data(contentsOf: home.settings) == Data("{\n  \"model\": \"opus\",\n}\n".utf8))
  }

  @Test("a setting that stops every hook is said under the Hooks row")
  func blocked() throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    try Data("{\n  \"disableAllHooks\": true\n}\n".utf8).write(to: home.settings)
    let model = ConnectModel(home: home, listening: 45871)
    #expect(model.blocked == "disableAllHooks is on in this settings file, so no hooks run")
    #expect(model.hint == "disableAllHooks is on in this settings file, so no hooks run.")
    // Connect still works: the setting is the person's, not ctxscope's.
    model.act()
    #expect(model.hooks == .on(port: 45871))
    #expect(model.hint?.hasPrefix("disableAllHooks is on") == true)
  }

  @Test("half written settings read as half connected")
  func partial() throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    // One of the two entries, which is what a write that stopped halfway
    // through leaves behind.
    var text = "{\n  \"hooks\": {\n    \"SessionEnd\": [{\"hooks\": [{\"type\": \"http\", "
    text += "\"url\": \"http://127.0.0.1:45871/ctxscope/hook\"}]}]\n  }\n}\n"
    try Data(text.utf8).write(to: home.settings)
    let model = ConnectModel(home: home, listening: 45871)
    #expect(model.hooks == .partial)
    #expect(model.buttonTitle == "Connect")
    #expect(model.needsReconnect)
    model.act()
    #expect(model.hooks == .on(port: 45871))
    #expect(!model.needsReconnect)
  }

  /// The five events ctxscope used to ask for are still in files written by
  /// an older one. They say nothing the file watcher does not say, so they
  /// read as an older wiring and connecting again takes them out.
  @Test("a file from an older ctxscope reads as older, and is brought up to date")
  func olderWiring() throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    var text = "{\n  \"hooks\": {\n"
    for event in ["UserPromptSubmit", "Stop", "SessionEnd"] {
      text += "    \"\(event)\": [{\"hooks\": [{\"type\": \"http\", "
      text += "\"url\": \"http://127.0.0.1:45871/ctxscope/hook\"}]}],\n"
    }
    text += "    \"SessionStart\": [{\"matcher\": \"startup|resume|clear|fork\", \"hooks\": "
    text += "[{\"type\": \"command\", \"command\": \"\(HookWiring.wakeCommand)\"}]}]\n  }\n}\n"
    try Data(text.utf8).write(to: home.settings)

    let model = ConnectModel(home: home, listening: 45871)
    #expect(model.hooks == .older)
    #expect(model.buttonTitle == "Connect")
    #expect(model.needsReconnect)

    model.act()
    #expect(model.hooks == .on(port: 45871))
    #expect(!model.needsReconnect)
    let written = try #require(try? Data(contentsOf: home.settings))
    #expect(try SettingsEdit.installedEvents(written) == Set(HookWiring.allEvents))
    let text2 = String(decoding: written, as: UTF8.self)
    #expect(!text2.contains("UserPromptSubmit"))
    #expect(!text2.contains("\"Stop\""))
  }
}
