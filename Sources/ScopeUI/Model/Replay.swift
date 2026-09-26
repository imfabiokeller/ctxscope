public import Foundation

@MainActor
@Observable
public final class Replay {
  public static let slowInterval = 0.48
  public static let fastInterval = 0.09
  public static let fastAbove = 100

  public private(set) var isRunning = false
  @ObservationIgnored public var onStep: (() -> Void)?

  @ObservationIgnored private var task: Task<Void, Never>?

  public init() {}

  public func start(requests: Int) {
    stop()
    isRunning = true
    schedule(requests > Self.fastAbove ? Self.fastInterval : Self.slowInterval)
  }

  // One task per step rather than a sleeping loop, so nothing outlives `stop()`:
  // the idle budget allows no timers.
  private func schedule(_ interval: Double) {
    task = Task { [weak self] in
      try? await Task.sleep(for: .seconds(interval))
      guard !Task.isCancelled, let self, isRunning else { return }
      onStep?()
      guard isRunning else { return }
      schedule(interval)
    }
  }

  public func stop() {
    task?.cancel()
    task = nil
    isRunning = false
  }

  deinit {
    task?.cancel()
  }
}
