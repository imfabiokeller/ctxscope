import Foundation
import ScopeCapture
import ScopeCore
import Testing

@testable import ScopeUI

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

    model.focus(session: recording.sessionID)
    model.start()
    await model.settle()

    #expect(model.watchedPaths.contains(url.path))
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

    #expect(model.watchedPaths.contains(url.path))
    #expect(!model.watchedPaths.contains(other.path))
    model.stop()
  }

  /// A file descriptor stays on the deleted inode, so only a scan can notice this.
  @Test("a transcript that is deleted is noticed, and the focus is let go")
  func transcriptDeleted() async throws {
    let url = try transcript()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let recording = SyntheticRecording.make()
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

    model.focus(session: nil)
    await model.settle()
    #expect(model.watchedPaths.isEmpty)

    model.focus(session: recording.sessionID)
    await model.settle()
    model.stop()
    #expect(model.watchedPaths.isEmpty)
  }
}
