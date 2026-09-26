internal import Foundation

extension InstrumentModel {
  func somethingChanged() {
    refresh()
    // A directory event says a file was added, not which, so new lane files are armed here.
    rearm()
  }

  func somethingVanished() {
    reloadSessions()
  }

  public var watchedPaths: [String] { watcher.watched }

  // Each lane file is watched: a directory event does not report a file inside it growing.
  func rearm() {
    guard let session = opened else { return watcher.watch([]) }
    let folder = session.url.deletingPathExtension()
    let lanes = folder.appending(path: "subagents")
    let urls =
      [session.url, session.url.deletingLastPathComponent(), folder, lanes]
      + laneFiles(in: lanes)
    watcher.watch(urls.filter { FileManager.default.fileExists(atPath: $0.path) })
  }

  private func laneFiles(in directory: URL) -> [URL] {
    let found = try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    return (found ?? []).filter { $0.pathExtension == "jsonl" }.sorted { $0.path < $1.path }
  }
}
