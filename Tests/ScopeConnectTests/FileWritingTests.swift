import Foundation
import Testing

@testable import ScopeConnect

/// Everything here runs in a temporary directory; no test may go near `~/.claude`.
@Suite("writing to somebody else's files")
struct FileWritingTests {
  private func temporary() throws -> ClaudeHome {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "ctxscope-files-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return ClaudeHome(root: root)
  }

  private func mode(_ url: URL) throws -> UInt16 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
  }

  @Test("the backup is never wider than the file it copies")
  func backupMode() throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    try original.write(to: home.settings)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: home.settings.path)

    let connect = ConnectService(home: home)
    try connect.apply(try connect.plan(.connect(port: 45871)))
    #expect(try mode(home.backup) == 0o600)
    #expect(try mode(home.settings) == 0o600)
  }

  @Test("a settings file ctxscope creates is readable by no other account")
  func createdMode() throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    let connect = ConnectService(home: home)
    try connect.apply(try connect.plan(.connect(port: 45871)))
    #expect(try mode(home.settings) == 0o600)
  }

  @Test("a settings file that is a symlink stays one, and the target is written")
  func symlink() throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    let dotfiles = home.root.appending(path: "dotfiles")
    try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
    let target = dotfiles.appending(path: "settings.json")
    let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    try original.write(to: target)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: target.path)
    try FileManager.default.createSymbolicLink(at: home.settings, withDestinationURL: target)

    let connect = ConnectService(home: home)
    try connect.apply(try connect.plan(.connect(port: 45871)))

    let kind = try FileManager.default.attributesOfItem(atPath: home.settings.path)[.type]
    #expect(kind as? FileAttributeType == .typeSymbolicLink)
    #expect(String(decoding: try Data(contentsOf: target), as: UTF8.self).contains("ctxscope/hook"))
    #expect(try mode(target) == 0o600)

    try connect.apply(try connect.plan(.disconnect))
    let stillALink = try FileManager.default.attributesOfItem(atPath: home.settings.path)[.type]
    #expect(stillALink as? FileAttributeType == .typeSymbolicLink)
    #expect(try Data(contentsOf: target) == original)
  }

  @Test("a link to nothing is left where it is")
  func danglingLink() throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    try FileManager.default.createSymbolicLink(
      at: home.settings, withDestinationURL: home.root.appending(path: "gone.json"))

    let connect = ConnectService(home: home)
    #expect(throws: Refusal.danglingLink("settings.json")) {
      try connect.plan(.connect(port: 45871))
    }
    let kind = try FileManager.default.attributesOfItem(atPath: home.settings.path)[.type]
    #expect(kind as? FileAttributeType == .typeSymbolicLink)
  }

  @Test("a link that goes round to itself is left where it is")
  func linkLoop() throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    let other = home.root.appending(path: "other.json")
    try FileManager.default.createSymbolicLink(at: home.settings, withDestinationURL: other)
    try FileManager.default.createSymbolicLink(at: other, withDestinationURL: home.settings)

    let connect = ConnectService(home: home)
    #expect(throws: Refusal.danglingLink("settings.json")) {
      try connect.plan(.connect(port: 45871))
    }
    let kind = try FileManager.default.attributesOfItem(atPath: home.settings.path)[.type]
    #expect(kind as? FileAttributeType == .typeSymbolicLink)
  }

  @Test("a link to a directory is left where it is")
  func linkToDirectory() throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    let folder = home.root.appending(path: "folder")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: home.settings, withDestinationURL: folder)

    #expect(throws: Refusal.danglingLink("settings.json")) {
      try ConnectService(home: home).plan(.connect(port: 45871))
    }
  }

  @Test("a read only settings file is refused rather than replaced")
  func readOnly() throws {
    let home = try temporary()
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: home.settings.path)
      try? FileManager.default.removeItem(at: home.root)
    }
    let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
    try original.write(to: home.settings)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: 0o444)], ofItemAtPath: home.settings.path)

    let connect = ConnectService(home: home)
    #expect(throws: Refusal.readOnly("settings.json")) {
      try connect.plan(.connect(port: 45871))
    }
    #expect(try Data(contentsOf: home.settings) == original)
  }

  @Test("the refusal says which file in plain words")
  func words() {
    #expect(
      Refusal.readOnly("settings.json").description
        == "settings.json is read only, so ctxscope left it alone")
    #expect(
      Refusal.danglingLink("settings.json").description
        == "settings.json is a link to nothing ctxscope could write, so it left it alone")
  }

  @Test("undo takes ctxscope's skill and leaves what somebody put beside it")
  func skillFolder() throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    let connect = ConnectService(home: home)
    try connect.apply(try connect.plan(.connect(port: 45871)))
    let notes = home.skillFolder.appending(path: "notes.md")
    try Data("mine\n".utf8).write(to: notes)

    try connect.apply(try connect.plan(.disconnect))
    #expect(!FileManager.default.fileExists(atPath: home.skill.path))
    #expect(FileManager.default.fileExists(atPath: notes.path))

    try FileManager.default.removeItem(at: notes)
    try connect.apply(try connect.plan(.connect(port: 45871)))
    try connect.apply(try connect.plan(.disconnect))
    #expect(!FileManager.default.fileExists(atPath: home.skillFolder.path))
  }

  @Test("a file is not read just to find out it is there")
  func exists() throws {
    let home = try temporary()
    defer { try? FileManager.default.removeItem(at: home.root) }
    let files = DiskFiles()
    #expect(!files.exists(home.settings))
    try files.write(Data("{}".utf8), to: home.settings, mode: 0o600)
    #expect(files.exists(home.settings))
    #expect(files.mode(of: home.settings) == 0o600)
    try files.remove(home.settings)
    #expect(!files.exists(home.settings))
    #expect(files.mode(of: home.settings) == nil)
  }
}
