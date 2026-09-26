import Foundation
import Testing

@testable import ScopeConnect

@Suite("a plan that has gone stale")
struct StalePlanTests {
  static let home = ClaudeHome(root: URL(fileURLWithPath: "/nowhere/.claude"))
  static let port: UInt16 = 45871

  private func service(_ files: MemoryFiles) -> ConnectService {
    ConnectService(home: Self.home, files: files)
  }

  @Test("a plan worked out before the file changed writes nothing")
  func stalePlan() throws {
    let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    let files = MemoryFiles([Self.home.settings.path: original])
    let connect = service(files)
    let plan = try connect.plan(.connect(port: Self.port))

    let moved = Data("{\n  \"model\": \"opus\",\n  \"permissions\": {}\n}\n".utf8)
    try files.write(moved, to: Self.home.settings)

    #expect(throws: Refusal.moved) { try connect.apply(plan) }
    #expect(try files.data(at: Self.home.settings) == moved)
    #expect(try files.data(at: Self.home.backup) == nil)

    let again = try connect.plan(.connect(port: Self.port))
    try connect.apply(again)
    let after = try #require(try files.data(at: Self.home.settings))
    #expect(String(decoding: after, as: UTF8.self).contains("\"permissions\": {}"))
    try connect.apply(try connect.plan(.disconnect))
    #expect(try files.data(at: Self.home.settings) == moved)
  }

  @Test("a plan that is refused leaves no backup behind")
  func staleLeavesNoBackup() throws {
    let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    let files = MemoryFiles([Self.home.settings.path: original])
    let connect = service(files)
    let plan = try connect.plan(.connect(port: Self.port))
    let moved = Data("{\n  \"model\": \"haiku\"\n}\n".utf8)
    try files.write(moved, to: Self.home.settings)

    #expect(throws: Refusal.moved) { try connect.apply(plan) }
    // A backup written before the check would hold the older file, and undo would trust it.
    #expect(try files.data(at: Self.home.backup) == nil)

    try connect.apply(try connect.plan(.connect(port: Self.port)))
    #expect(try files.data(at: Self.home.backup) == moved)
  }

  @Test("a disconnect plan is stale the same way")
  func staleDisconnect() throws {
    let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    let files = MemoryFiles([Self.home.settings.path: original])
    let connect = service(files)
    try connect.apply(try connect.plan(.connect(port: Self.port)))
    let plan = try connect.plan(.disconnect)
    let meddled = String(decoding: try files.data(at: Self.home.settings) ?? Data(), as: UTF8.self)
      .replacingOccurrences(of: "\"opus\"", with: "\"haiku\"")
    try files.write(Data(meddled.utf8), to: Self.home.settings)
    #expect(throws: Refusal.moved) { try connect.apply(plan) }
    #expect(
      String(decoding: try files.data(at: Self.home.settings) ?? Data(), as: UTF8.self)
        == meddled)
  }

  @Test("a plan made for a home with no settings file notices one appearing")
  func stalefromNothing() throws {
    let files = MemoryFiles()
    let connect = service(files)
    let plan = try connect.plan(.connect(port: Self.port))
    #expect(plan.basis == nil)
    try files.write(Data("{}\n".utf8), to: Self.home.settings)
    #expect(throws: Refusal.moved) { try connect.apply(plan) }
  }
}
