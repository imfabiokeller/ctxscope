import Foundation

@testable import ScopeUI

/// A clock a test drives, so three minutes take no time.
///
/// One of these, not one per file. A wait that is still parked when the clock
/// goes is resumed rather than dropped: a checked continuation that is
/// deallocated without being resumed prints "SWIFT TASK CONTINUATION MISUSE"
/// and leaves the task suspended for good.
final class HeldClock: WaitClock, @unchecked Sendable {
  private let lock = NSLock()
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var released = false
  private var seen: [Double] = []

  /// Every wait that was asked for, in order.
  var waited: [Double] {
    lock.lock()
    defer { lock.unlock() }
    return seen
  }

  func wait(seconds: Double) async {
    await withCheckedContinuation { continuation in
      lock.lock()
      seen.append(seconds)
      if released {
        lock.unlock()
        continuation.resume()
        return
      }
      waiters.append(continuation)
      lock.unlock()
    }
  }

  /// Lets every wait finish, in flight or still to come, which is what time
  /// passing looks like to a test.
  func release() {
    for waiter in take() { waiter.resume() }
    lock.lock()
    released = true
    lock.unlock()
  }

  deinit {
    for waiter in take() { waiter.resume() }
  }

  private func take() -> [CheckedContinuation<Void, Never>] {
    lock.lock()
    defer { lock.unlock() }
    let pending = waiters
    waiters = []
    return pending
  }
}
