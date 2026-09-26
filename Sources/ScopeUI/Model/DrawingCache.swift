internal import Foundation
internal import Observation

@MainActor
@Observable
package final class DrawingCache<Key: Hashable & Sendable, Value: Sendable> {
  @ObservationIgnored package private(set) var builds = 0
  @ObservationIgnored package private(set) var mainThreadBuilds = 0

  private var current: Entry?
  @ObservationIgnored private var pending: Key?
  @ObservationIgnored private let onBuild: @MainActor (Key, Bool) -> Void

  private struct Entry {
    let key: Key
    let value: Value
  }

  package init(onBuild: @escaping @MainActor (Key, Bool) -> Void = { _, _ in }) {
    self.onBuild = onBuild
  }

  // A renderer with no run loop never finishes a task, so it passes `synchronously`.
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
