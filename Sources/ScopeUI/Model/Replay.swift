public import Foundation

/// Replay: the playhead walking forward through the requests.
///
/// A task that sleeps between steps rather than a timer, so a window that is
/// not replaying has nothing scheduled at all. ctxscope has an idle budget
/// with no timers, and the window is held to the same rule.
@MainActor
@Observable
public final class Replay {
  /// Steps per second at the two window scales. A long recording plays
  /// faster, or a thousand requests would take eight minutes.
  public static let slowInterval = 0.48
  public static let fastInterval = 0.09
  /// Above this many requests, the fast interval is used.
  public static let fastAbove = 100

  public private(set) var isRunning = false
  /// Called once per step, on the main actor.
  @ObservationIgnored public var onStep: (() -> Void)?

  @ObservationIgnored private var task: Task<Void, Never>?

  public init() {}

  public func start(requests: Int) {
    stop()
    isRunning = true
    schedule(requests > Self.fastAbove ? Self.fastInterval : Self.slowInterval)
  }

  /// One step, which arms the next one. A loop that sleeps is a timer with
  /// extra steps: it keeps a task alive through its own sleep after the
  /// replay has been stopped, and it is the shape the idle budget forbids.
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
