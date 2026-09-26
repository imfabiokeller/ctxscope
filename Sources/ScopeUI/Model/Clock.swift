internal import Foundation

/// Waiting, as something a test can hold.
///
/// The idle window after a session's last write is three minutes of real time
/// in the app and no time at all in a test, which is the only way to test it
/// without spending three minutes on it.
public protocol WaitClock: Sendable {
  func wait(seconds: Double) async
}

/// The clock the app uses: one sleep per wait, nothing scheduled in between.
public struct RealClock: WaitClock {
  public init() {}

  public func wait(seconds: Double) async {
    try? await Task.sleep(for: .seconds(seconds))
  }
}
