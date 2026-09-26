internal import Dispatch
package import Foundation

/// Watches transcript files and the directories they live in, and says when
/// something changed.
///
/// File system events, never a timer. ctxscope keeps an idle budget of under
/// one percent CPU with no polling, and a window that follows a live session
/// is held to the same rule: while nothing is being written, nothing runs.
@MainActor
package final class SessionWatcher {
  /// Events arrive per write. A turn writes many lines in a burst, and reading
  /// once after the burst is both cheaper and what a reader wants to see.
  package static let settleSeconds = 0.12

  /// Called after a burst of changes has settled. Only the focused session is
  /// watched, so there is nothing to tell apart: whatever changed, it belongs
  /// to the session being shown.
  package var onChange: (() -> Void)?
  /// Called when a watched path was renamed or deleted. A descriptor follows
  /// the file it was opened on, not the name: after a rename it reports on an
  /// inode nobody is writing to any more, and the file under the old name is
  /// watched by nothing. So the source is dropped and whoever owns it is told
  /// to look again.
  package var onVanished: (() -> Void)?

  private var sources: [String: any DispatchSourceFileSystemObject] = [:]
  private var pending = false

  package init() {}

  /// Watches exactly these paths, dropping any that are no longer wanted.
  package func watch(_ urls: [URL]) {
    let wanted = Set(urls.map(\.path))
    for path in sources.keys where !wanted.contains(path) {
      sources.removeValue(forKey: path)?.cancel()
    }
    for url in urls where sources[url.path] == nil {
      guard let source = Self.makeSource(url) else { continue }
      let path = url.path
      source.setEventHandler { [weak self, weak source] in
        // Read here, on the queue the event came in on, because the flags
        // belong to the event.
        let gone = source.map { !$0.data.intersection([.rename, .delete]).isEmpty } ?? false
        Task { @MainActor [weak self] in
          guard let self else { return }
          guard gone else { return self.schedule() }
          self.drop(path)
          self.onVanished?()
        }
      }
      source.setCancelHandler {
        close(source.handle)
      }
      source.resume()
      sources[url.path] = source
    }
  }

  /// What is being watched right now. A watcher with nothing in it is a
  /// window that only moves when a hook fires, which is what the launch
  /// diagnostic and the tests check.
  package var watched: [String] { sources.keys.sorted() }

  /// Lets go of one path, which is what a file that is not there any more
  /// deserves.
  private func drop(_ path: String) {
    sources.removeValue(forKey: path)?.cancel()
  }

  package func stop() {
    for source in sources.values { source.cancel() }
    sources.removeAll()
  }

  deinit {
    for source in sources.values { source.cancel() }
  }

  private func schedule() {
    guard !pending else { return }
    pending = true
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(Self.settleSeconds))
      guard let self else { return }
      pending = false
      onChange?()
    }
  }

  private static func makeSource(_ url: URL) -> (any DispatchSourceFileSystemObject)? {
    let descriptor = Darwin.open(url.path, O_EVTONLY)
    guard descriptor >= 0 else { return nil }
    return DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .extend, .rename, .delete],
      queue: .main
    )
  }
}
