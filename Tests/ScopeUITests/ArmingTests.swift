import Foundation
import ScopeCapture
import ScopeCore
import Testing

@testable import ScopeUI

/// The watch is what makes the bars move while nothing else happens. It was
/// armed before the scan had answered, so it watched an empty list, and the
/// item only ever changed when a hook fired.
/// A feed that lists the session only while its transcript is on disk.
private struct VanishingFeed: SessionFeed {
  let recording: Recording
  let url: URL

  func sessions(reusing known: [String: SessionRef]) throws -> [SessionRef] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    return [
      SessionRef(
        id: recording.sessionID, project: "/p", url: url, title: "one",
        lastActivity: Date(), byteSize: 0, isLive: true)
    ]
  }

  func open(_ session: SessionRef, hints: ModelWindowHints) throws -> any OpenSession {
    GrowingSession(session: session, full: recording, requests: 20)
  }
}

@Suite("arming the watch")
@MainActor
struct ArmingTests {
  /// A session at a real path, so what the watcher is holding can be looked at
  /// rather than assumed.
  private func feed(at url: URL, recording: Recording) -> GrowingFeed {
    GrowingFeed(
      recording: recording,
      refs: [
        SessionRef(
          id: recording.sessionID, project: "/p", url: url, title: "one",
          lastActivity: Date(), byteSize: 0, isLive: true)
      ])
  }

  private func transcript() throws -> URL {
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "ctxscope-arm-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: "session.jsonl")
    try Data("{}\n".utf8).write(to: file)
    return file
  }

  @Test("a cold start with a focused session ends with that transcript watched")
  func coldStart() async throws {
    let url = try transcript()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let recording = SyntheticRecording.make()
    let model = InstrumentModel(feed: feed(at: url, recording: recording))

    // The order a launch does it in: the remembered focus, then start.
    model.focus(session: recording.sessionID)
    model.start()
    await model.settle()

    #expect(model.watchedPaths.contains(url.path))
    // And the directory it sits in, which is where a subagents directory
    // appears while the main transcript says nothing.
    #expect(model.watchedPaths.contains(url.deletingLastPathComponent().path))
    #expect(model.watchedPaths.count == 2)
    model.stop()
  }

  @Test("a write to the focused transcript is read with nothing else happening")
  func writeIsRead() async throws {
    let url = try transcript()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let recording = SyntheticRecording.make()
    let model = InstrumentModel(feed: feed(at: url, recording: recording))
    model.focus(session: recording.sessionID)
    model.start()
    await model.settle()
    let before = model.analysis?.requestCount ?? 0
    model.liveness.clear()

    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("{}\n".utf8))
    try handle.close()

    // The watcher reports once its burst has settled, and the read follows.
    try await WatcherTests.wait { (model.analysis?.requestCount ?? 0) > before }
    #expect((model.analysis?.requestCount ?? 0) > before)
    #expect(model.liveness.isLive)
    model.stop()
  }

  @Test("no other session on the machine is watched")
  func onlyTheFocusedOne() async throws {
    let url = try transcript()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let other = url.deletingLastPathComponent().appending(path: "other.jsonl")
    try Data("{}\n".utf8).write(to: other)
    let recording = SyntheticRecording.make()
    let model = InstrumentModel(
      feed: GrowingFeed(
        recording: recording,
        refs: [
          SessionRef(
            id: recording.sessionID, project: "/p", url: url, title: "one",
            lastActivity: Date(), byteSize: 0, isLive: true),
          SessionRef(
            id: "other", project: "/p", url: other, title: "two",
            lastActivity: Date().addingTimeInterval(-1), byteSize: 0, isLive: true),
        ]))
    model.focus(session: recording.sessionID)
    model.start()
    await model.settle()

    // The project directory is watched, because that is where this session's
    // subagents directory will appear. The other session's transcript is not:
    // a session that is not shown is not a session anything reads, and a
    // write inside a file is not a change to the directory holding it.
    #expect(model.watchedPaths.contains(url.path))
    #expect(!model.watchedPaths.contains(other.path))
    model.stop()
  }

  /// L1: the descriptor stays on the old inode, so nothing would ever be read
  /// again. One scan says whether this machine still has the session.
  @Test("a transcript that is deleted is noticed, and the focus is let go")
  func transcriptDeleted() async throws {
    let url = try transcript()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let recording = SyntheticRecording.make()
    // A feed that lists the session only while its file is there, which is
    // what a scan of the machine does.
    let model = InstrumentModel(
      feed: VanishingFeed(recording: recording, url: url))
    model.focus(session: recording.sessionID)
    model.start()
    await model.settle()
    #expect(model.recording?.sessionID == recording.sessionID)

    try FileManager.default.removeItem(at: url)
    try await WatcherTests.wait { model.list.focused == nil }
    #expect(model.list.focused == nil)
    #expect(model.analysis == nil)
    #expect(model.watchedPaths.allSatisfy { $0 != url.path })
    model.stop()
  }

  @Test("nothing focused watches nothing, and stopping lets go of everything")
  func nothingToWatch() async throws {
    let url = try transcript()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let recording = SyntheticRecording.make()
    let model = InstrumentModel(feed: feed(at: url, recording: recording))
    model.start()
    await model.settle()
    #expect(model.watchedPaths.isEmpty)

    model.focus(session: recording.sessionID)
    await model.settle()
    #expect(model.watchedPaths.contains(url.path))

    // Letting the focus go lets the watch go with it.
    model.focus(session: nil)
    await model.settle()
    #expect(model.watchedPaths.isEmpty)

    model.focus(session: recording.sessionID)
    await model.settle()
    model.stop()
    #expect(model.watchedPaths.isEmpty)
  }
}
