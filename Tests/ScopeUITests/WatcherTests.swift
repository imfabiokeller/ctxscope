import Foundation
import Testing

@testable import ScopeUI

@Suite("Session watcher")
@MainActor
struct WatcherTests {
  /// Waits for the report rather than a fixed time, which a loaded machine does not respect.
  static func wait(
    limit: Duration = .seconds(5), until ready: @MainActor () -> Bool
  ) async throws {
    let deadline = ContinuousClock.now + limit
    while ContinuousClock.now < deadline {
      if ready() { return }
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  private func temporary() throws -> URL {
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "ctxscope-watch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  @Test("a write to a watched file is reported once per burst")
  func fileWrites() async throws {
    let folder = try temporary()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "session.jsonl")
    try Data("one\n".utf8).write(to: file)

    let watcher = SessionWatcher()
    var calls = 0
    watcher.onChange = { calls += 1 }
    watcher.watch([file])

    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    for _ in 0..<5 { try handle.write(contentsOf: Data("more\n".utf8)) }
    try handle.close()

    try await Self.wait { calls > 0 }
    #expect(calls == 1)
    watcher.stop()
  }

  @Test("a new file in a watched directory is reported too")
  func directoryChanges() async throws {
    let folder = try temporary()
    defer { try? FileManager.default.removeItem(at: folder) }

    let watcher = SessionWatcher()
    var calls = 0
    watcher.onChange = { calls += 1 }
    watcher.watch([folder])

    try Data("{}".utf8).write(to: folder.appending(path: "new.jsonl"))
    try await Self.wait { calls > 0 }
    #expect(calls > 0)
    watcher.stop()
  }

  /// A descriptor follows its inode, so after a rename the watched name gets nothing.
  @Test("a watched file that is renamed is reported and let go of")
  func renamed() async throws {
    let folder = try temporary()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "session.jsonl")
    try Data("one\n".utf8).write(to: file)

    let watcher = SessionWatcher()
    var vanished = 0
    var changes = 0
    watcher.onVanished = { vanished += 1 }
    watcher.onChange = { changes += 1 }
    watcher.watch([file])
    #expect(watcher.watched == [file.path])

    try FileManager.default.moveItem(at: file, to: folder.appending(path: "rotated.jsonl"))
    try await Self.wait { vanished > 0 }
    #expect(vanished == 1)
    #expect(watcher.watched.isEmpty, "the old inode is still being watched")
    #expect(changes == 0, "a file that is gone is not a file that changed")
    watcher.stop()
  }

  @Test("a watched file that is deleted is reported and let go of")
  func deleted() async throws {
    let folder = try temporary()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "session.jsonl")
    try Data("one\n".utf8).write(to: file)

    let watcher = SessionWatcher()
    var vanished = 0
    watcher.onVanished = { vanished += 1 }
    watcher.watch([file])

    try FileManager.default.removeItem(at: file)
    try await Self.wait { vanished > 0 }
    #expect(vanished == 1)
    #expect(watcher.watched.isEmpty)
    watcher.stop()
  }

  @Test("nothing happening means nothing is called")
  func idle() async throws {
    let folder = try temporary()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "session.jsonl")
    try Data("one\n".utf8).write(to: file)

    let watcher = SessionWatcher()
    var calls = 0
    watcher.onChange = { calls += 1 }
    watcher.watch([file])
    try await Task.sleep(for: .seconds(SessionWatcher.settleSeconds * 4))
    #expect(calls == 0)
    watcher.stop()
  }
}
