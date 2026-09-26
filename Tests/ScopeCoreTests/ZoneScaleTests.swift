import Testing

@testable import ScopeCore

/// A step is a color and two numbers. The scale is data, so the numbers have
/// one home and a ruler and a lookup can never disagree.
@Suite("length steps")
struct ZoneScaleTests {
  @Test("length zones are absolute lengths, not shares of a window")
  func zones() throws {
    let scale = ZoneScale.default
    #expect(scale.steps == [50_000, 120_000, 200_000, 500_000])
    #expect(scale.zone(ofLength: 10_000) == .first)
    #expect(scale.zone(ofLength: 50_000) == .first)
    #expect(scale.zone(ofLength: 50_001) == .second)
    #expect(scale.zone(ofLength: 120_000) == .second)
    #expect(scale.zone(ofLength: 120_001) == .third)
    #expect(scale.zone(ofLength: 200_000) == .third)
    #expect(scale.zone(ofLength: 200_001) == .fourth)
    #expect(scale.zone(ofLength: 500_000) == .fourth)
    // One zone above 120k said the same about a 130k context and a 900k one.
    #expect(scale.zone(ofLength: 790_000) == .fifth)
    #expect(scale.zone(ofLength: 360_000) == .fourth)
    // The boundaries have one home, so a ruler and a lookup cannot disagree.
    #expect(scale.lowerBound(of: .first) == 0)
    for zone in LengthZone.allCases.dropLast() {
      let upper = try #require(scale.upperBound(of: zone))
      #expect(scale.zone(ofLength: upper) == zone)
      #expect(scale.zone(ofLength: upper + 1) > zone)
      #expect(scale.lowerBound(of: LengthZone.allCases[zone.step + 1]) == upper)
    }
    #expect(scale.upperBound(of: .fifth) == nil)
    // A scale with fewer numbers than gaps still answers for every zone.
    let short = ZoneScale(steps: [10_000])
    #expect(short.steps.count == LengthZone.allCases.count - 1)
    #expect(short.zone(ofLength: 5_000) == .first)
    #expect(short.zone(ofLength: 20_000) == .fifth)
    #expect(ZoneScale.forModel("anything") == .default)
  }

  /// A lane can change model half way through, and the zone scale is per
  /// model, so it is resolved from the request being asked about rather than
  /// from the first one.
  @Test("a model switch takes its zone scale with it")
  func zonesFollowTheModel() {
    let lane = Lane(
      id: .main,
      window: .given(200_000),
      segments: [],
      snapshots: (0..<3).map { index in
        Snapshot(
          index: index, requestID: nil, timestamp: Double(index),
          model: index < 2 ? "first" : "second",
          usage: RequestUsage(inputTokens: 1000))
      }
    )
    #expect(lane.zones(at: 0) == ZoneScale.forModel("first"))
    #expect(lane.zones(at: 2) == ZoneScale.forModel("second"))
    // Out of range asks about the nearest request there is, never crashes.
    #expect(lane.zones(at: 99) == ZoneScale.forModel("second"))
    #expect(lane.zones(at: -1) == ZoneScale.forModel("first"))
    let empty = Lane(id: .main, window: .given(1), segments: [], snapshots: [])
    #expect(empty.zones(at: 0) == .default)
  }
}
