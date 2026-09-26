import Foundation
import Testing

@testable import ScopeConnect

@Suite("settings that stop the hooks")
struct BlockedHooksTests {
  private func blocker(_ text: String, port: UInt16? = 45871) -> String? {
    HookWiring.blocker(in: Data(text.utf8), port: port)
  }

  @Test("nothing to say about a file with neither setting")
  func quiet() {
    #expect(blocker("{}") == nil)
    #expect(blocker("{\"model\": \"opus\"}") == nil)
    #expect(blocker("{\"disableAllHooks\": false}") == nil)
    #expect(blocker("not json") == nil)
  }

  @Test("disableAllHooks is named")
  func disabled() {
    #expect(
      blocker("{\"disableAllHooks\": true}")
        == "disableAllHooks is on in this settings file, so no hooks run")
  }

  @Test("an allow list that leaves our URL out is named")
  func allowList() {
    let missing = "allowedHttpHookUrls does not list ctxscope's URL, so its hooks would not run"
    #expect(blocker("{\"allowedHttpHookUrls\": []}") == missing)
    #expect(blocker("{\"allowedHttpHookUrls\": [\"http://example.com/x\"]}") == missing)
    #expect(blocker("{\"allowedHttpHookUrls\": [\"http://127.0.0.1:1/ctxscope/hook\"]}") == missing)
  }

  @Test("an allow list that covers our URL says nothing")
  func allowed() {
    #expect(blocker("{\"allowedHttpHookUrls\": [\"http://127.0.0.1:45871/ctxscope/hook\"]}") == nil)
    #expect(blocker("{\"allowedHttpHookUrls\": [\"http://127.0.0.1:45871/*\"]}") == nil)
    #expect(blocker("{\"allowedHttpHookUrls\": [\"*\"]}") == nil)
    #expect(
      blocker(
        "{\"allowedHttpHookUrls\": [\"http://127.0.0.1:45999/ctxscope/hook\"]}",
        port: 45999) == nil)
  }

  @Test("the doctor and the status both say so")
  func reported() throws {
    var text = "{\n  \"disableAllHooks\": true,\n  \"hooks\": {\n"
    text += "    \"Stop\": [{\"hooks\": [{\"type\": \"http\", "
    text += "\"url\": \"http://127.0.0.1:45871/ctxscope/hook\"}]}]\n  }\n}\n"
    let files = MemoryFiles([
      ClaudeHome(root: URL(fileURLWithPath: "/nowhere")).settings.path:
        Data(text.utf8)
    ])
    let service = ConnectService(
      home: ClaudeHome(root: URL(fileURLWithPath: "/nowhere")), files: files)
    #expect(try service.status().blocked?.hasPrefix("disableAllHooks is on") == true)
    let report = service.report(probe: false)
    #expect(report.lines.contains { $0.hasPrefix("blocked        disableAllHooks is on") })
    #expect(!report.isHealthy)
  }
}
