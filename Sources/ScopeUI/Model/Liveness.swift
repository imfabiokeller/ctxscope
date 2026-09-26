public import Foundation

/// Whether the session being followed is being written to now.
///
/// One place decides this, from one fact: when the session last gained
/// anything. A scan's own `isLive` flag is only as fresh as the last scan, and
/// a scan only happens when a directory changes, so continuing a session that
/// had been idle for three minutes left the menu bar dimmed for the whole turn,
/// and a session that ended stayed live until something unrelated happened.
///
/// Dropping it again is one cancellable wait, re-armed on each write. Nothing
/// polls, and nothing is scheduled once it has dropped.
@MainActor
@Observable
public final class Liveness {
  /// A session written to this recently is live. The same number the scan
  /// uses, because there is only one rule.
  public static let window: TimeInterval = 180

  public private(set) var isLive = false
  /// Called when it drops on its own. Whoever is following a session because
  /// a hook said so has to stop believing that at the same moment.
  @ObservationIgnored public var onDrop: (() -> Void)?

  private let clock: any WaitClock
  @ObservationIgnored private var drop: Task<Void, Never>?

  public init(clock: any WaitClock = RealClock()) {
    self.clock = clock
  }

  /// The followed session was last written to then. Live until that is
  /// `window` old, whether that is now or in the past.
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

  /// Nothing is being followed. Used when the session is replaced and when
  /// the app stops.
  public func clear() {
    drop?.cancel()
    drop = nil
    isLive = false
  }
}
