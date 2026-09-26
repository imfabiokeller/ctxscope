public import Foundation

@MainActor
@Observable
public final class Liveness {
  // Must match `SessionDiscovery.liveWindow` in ScopeCapture.
  public static let window: TimeInterval = 180

  public private(set) var isLive = false
  @ObservationIgnored public var onDrop: (() -> Void)?

  private let clock: any WaitClock
  @ObservationIgnored private var drop: Task<Void, Never>?

  public init(clock: any WaitClock = RealClock()) {
    self.clock = clock
  }

  public func saw(activity: Date, now: Date = Date()) {
    let left = Self.window - now.timeIntervalSince(activity)
    drop?.cancel()
    drop = nil
    guard left > 0 else {
      let was = isLive
      isLive = false
      if was { onDrop?() }
      return
    }
    isLive = true
    drop = Task { [weak self] in
      guard let self else { return }
      await clock.wait(seconds: left)
      guard !Task.isCancelled else { return }
      isLive = false
      drop = nil
      onDrop?()
    }
  }

  public func clear() {
    drop?.cancel()
    drop = nil
    isLive = false
  }
}
