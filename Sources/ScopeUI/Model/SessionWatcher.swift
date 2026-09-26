internal import Dispatch
package import Foundation

@MainActor
package final class SessionWatcher {
  package static let settleSeconds = 0.12

  package var onChange: (() -> Void)?
  // A descriptor follows the inode, not the name: after a rename or delete the
  // path must be watched again.
  package var onVanished: (() -> Void)?

  private var sources: [String: any DispatchSourceFileSystemObject] = [:]
  private var pending = false

  package init() {}

  package func watch(_ urls: [URL]) {
    let wanted = Set(urls.map(\.path))
    for path in sources.keys where !wanted.contains(path) {
      sources.removeValue(forKey: path)?.cancel()
    }
    for url in urls where sources[url.path] == nil {
      guard let source = Self.makeSource(url) else { continue }
      let path = url.path
      source.setEventHandler { [weak self, weak source] in
        // The flags belong to this event, so they are read here on the event's queue.
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

  package var watched: [String] { sources.keys.sorted() }

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
