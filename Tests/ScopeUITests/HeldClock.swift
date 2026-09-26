import Foundation

@testable import ScopeUI

/// Parked waits are resumed, never dropped: a checked continuation deallocated without a
/// resume reports "SWIFT TASK CONTINUATION MISUSE" and leaves the task suspended.
final class HeldClock: WaitClock, @unchecked Sendable {
  private let lock = NSLock()
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var released = false
  private var seen: [Double] = []

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
