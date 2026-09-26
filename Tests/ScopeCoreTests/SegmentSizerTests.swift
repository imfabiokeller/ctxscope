import Testing

@testable import ScopeCore

@Suite("SegmentSizer")
struct SegmentSizerTests {
  private func pending(
    _ band: Band,
    characters: Int,
    group: Int? = nil,
    contentClass: ContentClass = .prose
  ) -> PendingSegment {
    PendingSegment(
      band: band,
      label: "\(band.rawValue)",
      characters: characters,
      contentClass: contentClass,
      contentHash: UInt64(characters),
      group: group
    )
  }

  @Test("the first request puts everything it cannot explain into the prefix")
  func firstRequestDerivesPrefix() {
    var sizer = SegmentSizer()
    let result = sizer.size(
      SizingRequest(
        measuredTotal: 50_000,
        entering: [pending(.user, characters: 400)],
        leavingTokens: 0,
        groupTotals: [:],
        absorbSurplus: true
      )
    )
    #expect(result.tokens.count == 1)
    #expect(result.unallocated > 49_000)
    #expect(result.tokens[0].value + result.unallocated == 50_000)
    #expect(result.residualTokens == 0)
  }

  @Test("later requests normalize estimates onto the measured delta")
  func laterRequestsNormalize() {
    var sizer = SegmentSizer()
    _ = sizer.size(
      SizingRequest(
        measuredTotal: 10_000,
        entering: [pending(.user, characters: 100)],
        leavingTokens: 0,
        groupTotals: [:],
        absorbSurplus: true
      )
    )
    let result = sizer.size(
      SizingRequest(
        measuredTotal: 12_000,
        entering: [pending(.read, characters: 3000), pending(.bash, characters: 500)],
        leavingTokens: 0,
        groupTotals: [:],
        absorbSurplus: false
      )
    )
    #expect(result.tokens.reduce(0) { $0 + $1.value } == 2000)
    #expect(result.appendedTokens == 2000)
    #expect(result.tokens.allSatisfy { $0.grade == .estimated })
  }

  @Test("a measured group of one keeps the measured grade")
  func measuredGroupOfOne() {
    var sizer = SegmentSizer()
    _ = sizer.size(
      SizingRequest(
        measuredTotal: 1000, entering: [], leavingTokens: 0, groupTotals: [:],
        absorbSurplus: true))
    let result = sizer.size(
      SizingRequest(
        measuredTotal: 3000,
        entering: [pending(.think, characters: 900, group: 1), pending(.read, characters: 2000)],
        leavingTokens: 0,
        groupTotals: [1: 800],
        absorbSurplus: false
      )
    )
    #expect(result.tokens[0] == Tokens(800, .measured))
    #expect(result.tokens.reduce(0) { $0 + $1.value } == 2000)
  }

  @Test("a split inside a measured group is an estimate of a measured whole")
  func measuredGroupSplit() {
    var sizer = SegmentSizer()
    _ = sizer.size(
      SizingRequest(
        measuredTotal: 1000, entering: [], leavingTokens: 0, groupTotals: [:],
        absorbSurplus: true))
    let result = sizer.size(
      SizingRequest(
        measuredTotal: 2000,
        entering: [
          pending(.asst, characters: 300, group: 1),
          pending(.call, characters: 100, group: 1, contentClass: .json),
        ],
        leavingTokens: 0,
        groupTotals: [1: 600],
        absorbSurplus: false
      )
    )
    // The group is measured at 600; the 400 it cannot explain goes to the unobserved prefix.
    #expect(result.tokens.map(\.value).reduce(0, +) == 600)
    #expect(result.unallocated == 400)
    #expect(result.tokens.allSatisfy { $0.grade == .derived })
  }

  @Test("groups that overshoot the delta are shrunk, never made negative")
  func overshootingGroups() {
    var sizer = SegmentSizer()
    _ = sizer.size(
      SizingRequest(
        measuredTotal: 5000, entering: [], leavingTokens: 0, groupTotals: [:],
        absorbSurplus: true))
    let result = sizer.size(
      SizingRequest(
        measuredTotal: 5100,
        entering: [
          pending(.asst, characters: 500, group: 1),
          pending(.read, characters: 9000),
        ],
        leavingTokens: 0,
        groupTotals: [1: 4000],
        absorbSurplus: false
      )
    )
    #expect(result.tokens.map(\.value).reduce(0, +) == 100)
    #expect(result.tokens.allSatisfy { $0.value >= 0 })
    #expect(result.tokens[0].grade != .measured)
  }

  @Test("what leaves comes off the carried total")
  func leavingReducesCarried() {
    var sizer = SegmentSizer()
    _ = sizer.size(
      SizingRequest(
        measuredTotal: 10_000, entering: [pending(.user, characters: 100)], leavingTokens: 0,
        groupTotals: [:], absorbSurplus: true))
    #expect(sizer.carriedTokens == 10_000)
    let result = sizer.size(
      SizingRequest(
        measuredTotal: 4000,
        entering: [pending(.asst, characters: 200)],
        leavingTokens: 7000,
        groupTotals: [:],
        absorbSurplus: false
      )
    )
    #expect(result.tokens[0].value == 1000)
    #expect(sizer.carriedTokens == 4000)
  }
}
