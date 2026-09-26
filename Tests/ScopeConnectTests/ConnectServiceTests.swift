import Foundation
import Testing

@testable import ScopeConnect

@Suite("connect and disconnect")
struct ConnectServiceTests {
  static let home = ClaudeHome(root: URL(fileURLWithPath: "/nowhere/.claude"))
  static let port: UInt16 = 45871

  private func service(_ files: MemoryFiles) -> ConnectService {
    ConnectService(home: Self.home, files: files)
  }

  @Test("a home with nothing in it gains a settings file, a backup and a skill")
  func fromNothing() throws {
    let files = MemoryFiles()
    let connect = service(files)
    let plan = try connect.plan(.connect(port: Self.port))
    #expect(!plan.isEmpty)
    #expect(plan.skill == .install)
    #expect(plan.diff().contains("+   \"hooks\": {"))
    // Nothing has been written while there is only a plan.
    #expect(files.paths.isEmpty)

    try connect.apply(plan)
    let status = try connect.status()
    #expect(status.isConnected)
    #expect(status.port == Self.port)
    #expect(status.hasSkill)
    #expect(!status.isPartial)
    // There was no file to copy, so there is no backup pretending there was.
    #expect(try files.data(at: Self.home.backup) == nil)
    #expect(try files.data(at: Self.home.skill) == ConnectSkill.data)
  }

  @Test("undo of that takes the settings file away again")
  func undoFromNothing() throws {
    let files = MemoryFiles()
    let connect = service(files)
    try connect.apply(try connect.plan(.connect(port: Self.port)))
    let undo = try connect.plan(.disconnect)
    #expect(undo.removesSettings)
    try connect.apply(undo)
    #expect(files.paths.isEmpty)
    #expect(try connect.status().isConnected == false)
  }

  @Test("undo puts an existing settings file back byte for byte")
  func undoIsByteIdentical() throws {
    let original = Data("{\n  \"model\": \"opus\",\n  \"env\": {\"A\": \"b\"}\n}\n".utf8)
    let files = MemoryFiles([Self.home.settings.path: original])
    let connect = service(files)
    try connect.apply(try connect.plan(.connect(port: Self.port)))
    #expect(try files.data(at: Self.home.settings) != original)
    #expect(try files.data(at: Self.home.backup) == original)

    try connect.apply(try connect.plan(.disconnect))
    #expect(try files.data(at: Self.home.settings) == original)
    #expect(try files.data(at: Self.home.backup) == nil)
    #expect(try files.data(at: Self.home.skill) == nil)
  }

  @Test(
    "a settings file that holds only whitespace is a file, not an absence",
    arguments: ["\n", "   \n\n  ", "\t"])
  func blankFile(text: String) throws {
    let original = Data(text.utf8)
    let files = MemoryFiles([Self.home.settings.path: original])
    let connect = service(files)
    try connect.apply(try connect.plan(.connect(port: Self.port)))
    #expect(try files.data(at: Self.home.backup) == original)
    #expect(
      try SettingsEdit.installedPorts(try files.data(at: Self.home.settings) ?? Data())
        .count == HookWiring.events.count)

    let undo = try connect.plan(.disconnect)
    #expect(!undo.removesSettings)
    try connect.apply(undo)
    #expect(try files.data(at: Self.home.settings) == original)
  }

  @Test("connecting twice changes nothing the second time")
  func idempotent() throws {
    let files = MemoryFiles([Self.home.settings.path: Data("{}\n".utf8)])
    let connect = service(files)
    try connect.apply(try connect.plan(.connect(port: Self.port)))
    let written = try files.data(at: Self.home.settings)
    let again = try connect.plan(.connect(port: Self.port))
    #expect(again.isEmpty)
    try connect.apply(again)
    #expect(try files.data(at: Self.home.settings) == written)
  }

  @Test("Claude's settings file is written once, and never again for its own sake")
  func writtenOnce() throws {
    let files = MemoryFiles([Self.home.settings.path: Data("{\n  \"model\": \"opus\"\n}\n".utf8)])
    let connect = service(files)
    try connect.apply(try connect.plan(.connect(port: Self.port)))
    let written = try files.data(at: Self.home.settings)

    // Everything is in place, so there is nothing to write, whether or not
    // the panel is opened again.
    for _ in 0..<3 {
      let plan = try connect.plan(.connect(port: Self.port))
      #expect(plan.isEmpty)
      #expect(!plan.changesSettings)
      #expect(plan.skill == .none)
      try connect.apply(plan)
      #expect(try files.data(at: Self.home.settings) == written)
    }

    // The only later writes: a port that truly cannot be used, and undo.
    let moved = try connect.plan(.connect(port: 45999))
    #expect(!moved.isEmpty)
    #expect(!(try connect.plan(.disconnect)).isEmpty)
  }

  @Test("the backup is written once and never overwritten")
  func backupIsWrittenOnce() throws {
    let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    let files = MemoryFiles([Self.home.settings.path: original])
    let connect = service(files)
    try connect.apply(try connect.plan(.connect(port: Self.port)))
    try connect.apply(try connect.plan(.connect(port: 45999)))
    #expect(try files.data(at: Self.home.backup) == original)
    try connect.apply(try connect.plan(.disconnect))
    #expect(try files.data(at: Self.home.settings) == original)
  }

  @Test("a settings file changed in between keeps the change")
  func changedInBetween() throws {
    let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    let files = MemoryFiles([Self.home.settings.path: original])
    let connect = service(files)
    try connect.apply(try connect.plan(.connect(port: Self.port)))
    let meddled = String(decoding: try files.data(at: Self.home.settings) ?? Data(), as: UTF8.self)
      .replacingOccurrences(of: "\"model\": \"opus\"", with: "\"model\": \"haiku\"")
    try files.write(Data(meddled.utf8), to: Self.home.settings)

    try connect.apply(try connect.plan(.disconnect))
    let after = try files.data(at: Self.home.settings) ?? Data()
    #expect(try SettingsEdit.installedPorts(after).isEmpty)
    #expect(try JSONSpan.parse(after)["model"]?.text == "haiku")
  }

  @Test("a malformed settings file is refused and nothing is written")
  func malformed() throws {
    let broken = Data("{\n  \"model\": \"opus\",\n}\n".utf8)
    let files = MemoryFiles([Self.home.settings.path: broken])
    let connect = service(files)
    #expect(throws: Refusal.notJSON("a key was expected on line 3")) {
      try connect.plan(.connect(port: Self.port))
    }
    #expect(files.paths == [Self.home.settings.path])
    #expect(try files.data(at: Self.home.settings) == broken)
  }

  @Test("one rule decides whether the hooks would reach this ctxscope")
  func needsReconnect() throws {
    let files = MemoryFiles()
    let connect = service(files)
    // Nothing written: nothing to reconnect.
    #expect(try connect.status().needsReconnect(listening: Self.port) == false)

    try connect.apply(try connect.plan(.connect(port: Self.port)))
    #expect(try connect.status().needsReconnect(listening: Self.port) == false)
    #expect(try connect.status().needsReconnect(listening: 45999))
    #expect(try connect.status().needsReconnect(listening: nil))

    // Connecting again on the new port settles it.
    try connect.apply(try connect.plan(.connect(port: 45999)))
    #expect(try connect.status().needsReconnect(listening: 45999) == false)

    // And a wake command an older ctxscope wrote is a reconnect too: it reads
    // as connected while it would turn an off ctxscope on.
    let current = try #require(try files.data(at: Self.home.settings))
    let old = String(decoding: current, as: UTF8.self)
      .replacingOccurrences(of: HookWiring.wakeCommand, with: "open -g ctxscope://wake || true")
    try files.write(Data(old.utf8), to: Self.home.settings)
    #expect(try connect.status().hasStaleWake)
    #expect(try connect.status().needsReconnect(listening: 45999))
    try connect.apply(try connect.plan(.connect(port: 45999)))
    #expect(try connect.status().needsReconnect(listening: 45999) == false)
  }

  @Test("status reports a half written state")
  func partial() throws {
    var text = "{\n  \"hooks\": {\n"
    text += "    \"SessionEnd\": [{\"hooks\": [{\"type\": \"http\", "
    text += "\"url\": \"http://127.0.0.1:45871/ctxscope/hook\"}]}]\n  }\n}\n"
    let files = MemoryFiles([Self.home.settings.path: Data(text.utf8)])
    let status = try service(files).status()
    #expect(status.isConnected)
    #expect(status.isPartial, "the entry that starts ctxscope is not there")
    #expect(status.events == ["SessionEnd"])
    #expect(status.retired.isEmpty)
    #expect(status.needsReconnect(listening: 45871))
  }

  @Test("the skill is the documented shape")
  func skillShape() {
    let lines = ConnectSkill.text.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.first == "---")
    #expect(lines.contains("name: ctxscope"))
    #expect(lines.contains { $0.hasPrefix("description: ") })
    // Without this the injected command aborts the invocation outside auto
    // mode, which is what the skills reference says an ask rule does. The
    // space form and the `:*` suffix are equivalent; this is the one the
    // permission dialog writes.
    #expect(lines.contains("allowed-tools: Bash(open *)"))
    #expect(lines.contains("disable-model-invocation: true"))
    // The rule has to cover the command the body runs.
    #expect(ConnectSkill.text.contains("!`open \""))
    #expect(ConnectSkill.text.contains("ctxscope://show?session=${CLAUDE_SESSION_ID}"))
    // The URL is built in one place, not written out twice.
    #expect(
      ConnectSkill.text.contains(ScopeURL.show(session: ScopeURL.sessionPlaceholder)))
    #expect(Self.home.skill.path.hasSuffix("/skills/ctxscope/SKILL.md"))
  }

  @Test("a SKILL.md somebody wrote themselves is left where it is")
  func handEditedSkill() throws {
    let files = MemoryFiles([Self.home.skill.path: Data("---\nname: mine\n---\n".utf8)])
    let connect = service(files)
    let plan = try connect.plan(.disconnect)
    #expect(plan.skill == .keepEdited)
    try connect.apply(plan)
    #expect(try files.data(at: Self.home.skill) == Data("---\nname: mine\n---\n".utf8))
  }

  @Test("ours is removed, and connecting again puts it back")
  func ourSkill() throws {
    let files = MemoryFiles()
    let connect = service(files)
    try connect.apply(try connect.plan(.connect(port: Self.port)))
    #expect(try files.data(at: Self.home.skill) == ConnectSkill.data)
    let off = try connect.plan(.disconnect)
    #expect(off.skill == .remove)
    try connect.apply(off)
    #expect(try files.data(at: Self.home.skill) == nil)
  }
}

/// `doctor` is the one command pointed at the real files, and the one line
/// that can save a confusing hour is which copy of ctxscope a wake would
/// start.
@Suite("what doctor says about the scheme")
struct SchemeLineTests {
  private func report(handler: URL?, copies: [URL], running: URL?) -> ConnectReport {
    ConnectReport(
      home: URL(fileURLWithPath: "/tmp/home"), status: nil, listener: nil,
      schemeHandler: handler, schemeCopies: copies, runningBundle: running, failure: nil)
  }

  private let build = URL(fileURLWithPath: "/repo/build/ctxscope.app")
  private let installed = URL(fileURLWithPath: "/Applications/ctxscope.app")

  private func schemeLine(_ report: ConnectReport) -> String {
    report.lines.first { $0.hasPrefix("url scheme") } ?? ""
  }

  @Test("it says when the handler is this copy")
  func thisCopy() {
    let line = schemeLine(report(handler: build, copies: [build], running: build))
    #expect(line.contains("which is this copy"))
    #expect(!line.contains("copies registered"))
  }

  @Test("it says when the handler is another copy, and names it")
  func anotherCopy() {
    let line = schemeLine(report(handler: installed, copies: [installed, build], running: build))
    #expect(line.contains("not this copy at /repo/build/ctxscope.app"))
    #expect(line.contains("2 copies registered"))
    #expect(line.contains("/repo/build/ctxscope.app"))
  }

  @Test("the command line tool is not a bundle, and says so")
  func notABundle() {
    let line = schemeLine(report(handler: installed, copies: [installed], running: nil))
    #expect(line.contains("not run from a bundle"))
  }

  @Test("no handler at all is one line too")
  func noHandler() {
    #expect(schemeLine(report(handler: nil, copies: [], running: nil)).contains("no handler"))
  }
}
