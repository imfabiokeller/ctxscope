import Foundation
import ScopeCore
import Testing

@testable import ScopeUI

/// A session with one request, and one with two.
///
/// A window opened on a brand new session must not read 0 / 0 or say "since
/// request 0, 0 requests". Everything here is that case.
@Suite("the shortest lanes")
struct ShortLaneTests {
  @Test("a lane of one request reads as request one of one")
  func numbering() {
    #expect(RequestNumber.counter(0, of: 1) == "1 / 1")
    #expect(RequestNumber.counter(1, of: 2) == "2 / 2")
    #expect(RequestNumber.name(0) == "request 1")
    // A lane that has no requests yet says so rather than claiming one.
    #expect(RequestNumber.counter(0, of: 0) == "0 / 0")
  }

  @Test("the popover's chart of a short lane is a bar per request, and no more")
  func popoverChart() {
    let one = SparkBars.make(totals: [61_000], breaks: [], window: 200_000, capacity: 164)
    #expect(one == [SparkBar(height: 0.305, isBreak: false)])

    let two = SparkBars.make(
      totals: [61_000, 92_000], breaks: [1], window: 200_000, capacity: 164)
    #expect(two.map(\.height) == [0.305, 0.46])
    #expect(two.map(\.isBreak) == [false, true])

    #expect(SparkBars.make(totals: [], breaks: [], window: 200_000, capacity: 164).isEmpty)
  }
}
