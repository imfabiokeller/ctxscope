internal import Foundation

public protocol WaitClock: Sendable {
  func wait(seconds: Double) async
}

public struct RealClock: WaitClock {
  public init() {}

  public func wait(seconds: Double) async {
    try? await Task.sleep(for: .seconds(seconds))
  }
}
