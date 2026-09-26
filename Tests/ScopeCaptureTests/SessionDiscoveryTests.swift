import Foundation
import Testing

@testable import ScopeCapture

/// The project a session is filed under, read back as the folder it ran in.
@Suite("session discovery")
struct SessionDiscoveryTests {
  /// A projects folder holding one transcript under `slug`, whose entries say
  /// they ran in `cwd`.
  private static func projects(slug: String, cwd: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "ctxscope-discovery-\(UUID().uuidString)")
    let folder = root.appending(path: slug)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let lines = [
      #"{"type":"queue-operation","operation":"enqueue"}"#,
      #"{"type":"user","uuid":"a","cwd":"\#(cwd)","message":{"role":"user","content":"hi"}}"#,
    ]
    try Data((lines.joined(separator: "\n") + "\n").utf8)
      .write(to: folder.appending(path: "s1.jsonl"))
    return root
  }

  @Test("a hyphen in a folder name survives when the transcript says where it ran")
  func hyphenatedProject() throws {
    let root = try Self.projects(slug: "-home-me-code-api-client", cwd: "/home/me/code/api-client")
    defer { try? FileManager.default.removeItem(at: root) }
    let sessions = try SessionDiscovery(root: root).sessions()
    #expect(sessions.map(\.project) == ["/home/me/code/api-client"])
  }

  @Test("a working directory that is not the folder's is not believed")
  func mismatchedDirectory() throws {
    let root = try Self.projects(slug: "-home-me-code-api-client", cwd: "/home/me/elsewhere")
    defer { try? FileManager.default.removeItem(at: root) }
    let sessions = try SessionDiscovery(root: root).sessions()
    #expect(sessions.map(\.project) == ["/home/me/code/api/client"])
  }

  @Test("the folder name is the harness's: every other character is a hyphen")
  func slugRule() {
    #expect(
      ClaudeCodeAdapter.folderName(of: "/Users/me/code/api-client") == "-Users-me-code-api-client")
    #expect(ClaudeCodeAdapter.folderName(of: "/tmp/demo.x_y") == "-tmp-demo-x-y")
  }
}
