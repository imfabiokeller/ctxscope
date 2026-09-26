internal import Foundation
internal import Observation

/// Keeps the last drawing of a chart, and draws the next one off the main
/// thread. The one place a chart's picture is cached: the timeline keeps its
/// columns here.
///
/// It is a class its owner keeps rather than view state because a renderer
/// with no run loop never finishes a task, so it asks for the drawing
/// synchronously, and in a real window a view that
/// asks for a drawing the cache does not have starts it off the main actor and
/// gets nothing for that frame. The drawing is observed, so the frame that
/// finds it happens by itself.
@MainActor
@Observable
package final class DrawingCache<Key: Hashable & Sendable, Value: Sendable> {
  /// How many drawings were made, and how many of those on the main thread.
  /// Zero on the main thread in the app, and every one of them under a
  /// renderer.
  @ObservationIgnored package private(set) var builds = 0
  @ObservationIgnored package private(set) var mainThreadBuilds = 0

  private var current: Entry?
  /// The draw in flight, so a view that asks for the same drawing on every
  /// frame while it is being made starts it once.
  @ObservationIgnored private var pending: Key?
  /// Told of every drawing made, with its key and whether it was made on the
  /// main thread, for counts kept across caches.
  @ObservationIgnored private let onBuild: @MainActor (Key, Bool) -> Void

  private struct Entry {
    let key: Key
    let value: Value
  }

  package init(onBuild: @escaping @MainActor (Key, Bool) -> Void = { _, _ in }) {
    self.onBuild = onBuild
  }

  /// The drawing for a key, or nothing while it is being made.
  ///
  /// `synchronously` is for a renderer with no run loop. A window passes false
  /// and never blocks on a draw.
  package func value(
    for key: Key, synchronously: Bool, draw: @escaping @Sendable () -> Value?
  ) -> Value? {
    if let current, current.key == key { return current.value }
    guard synchronously else {
      start(key, draw: draw)
      return nil
    }
    let made = draw()
    current = made.map { Entry(key: key, value: $0) }
    if made != nil { count(key, onMain: true) }
    return made
  }

  private func start(_ key: Key, draw: @escaping @Sendable () -> Value?) {
    guard pending != key else { return }
    pending = key
    Task { [weak self] in await self?.make(key, draw: draw) }
  }

  private func make(_ key: Key, draw: @escaping @Sendable () -> Value?) async {
    let made = await Task.detached(priority: .userInitiated) { draw() }.value
    if pending == key { pending = nil }
    guard let made else { return }
    count(key, onMain: false)
    current = Entry(key: key, value: made)
  }

  private func count(_ key: Key, onMain: Bool) {
    builds += 1
    if onMain { mainThreadBuilds += 1 }
    onBuild(key, onMain)
  }
}
