import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture

@Suite("Retirement")
struct RetirementTests {
  private func segment(_ band: Band, _ tokens: Int, born: Int) -> Segment {
    Segment(
      id: SegmentID(0),
      band: band,
      label: band.rawValue,
      tokens: Tokens(tokens, .estimated),
      characters: tokens * 3,
      contentClass: .prose,
      born: born,
      contentHash: UInt64(tokens)
    )
  }

  private func lane(_ shape: [(Band, Int)]) -> ([Segment], Set<Int>) {
    var segments: [Segment] = []
    for (index, item) in shape.enumerated() {
      var one = segment(item.0, item.1, born: 0)
      one = Segment(
        id: SegmentID(index), band: one.band, label: one.label, tokens: one.tokens,
        characters: one.characters, contentClass: one.contentClass, born: 0,
        contentHash: one.contentHash)
      segments.append(one)
    }
    return (segments, Set(segments.indices))
  }

  @Test("nothing is retired when the totals already agree")
  func noOverhang() {
    var (segments, live) = lane([(.think, 100), (.read, 900)])
    let result = LaneBuilder.retire(
      overhang: 0, enteringEstimate: 50, at: 3, segments: &segments, liveSlots: &live)
    #expect(!result.didRetire)
    #expect(live.count == 2)
  }

  /// F3: a set that frees far more room than anything entering can take would
  /// turn a third of itself into Unattributed. That is the hypothesis being
  /// wrong, so it is rejected and the best fitting set is taken instead.
  @Test("the thinking hypothesis is rejected when it would leave a third unattributed")
  func rejectedWhenItLeavesTooMuch() {
    var (segments, live) = lane([
      (.think, 6000), (.think, 6000), (.read, 3000), (.user, 2000),
    ])
    // Thinking is 12,000 and the overhang is 4,000, so 8,000 would be handed
    // to something the estimator says is 3,000. The 5,000 left over is past a
    // third of what the set freed.
    let result = LaneBuilder.retire(
      overhang: 4000, enteringEstimate: 3000, at: 5, segments: &segments, liveSlots: &live)
    #expect(result.hypothesis == "best fitting set of older content")
    #expect(result.tokens >= 4000)
    // The thinking hypothesis would have taken both thinking blocks.
    #expect(!(segments[0].died != nil && segments[1].died != nil))
  }

  @Test("all live thinking leaving is preferred when it fits what is entering")
  func setHypothesis() {
    var (segments, live) = lane([
      (.think, 400), (.think, 500), (.read, 3000), (.user, 200),
    ])
    // Thinking is 900. An overhang of 700 leaves 200 for what is entering,
    // and the estimate is 210, so the set explains the drop.
    let result = LaneBuilder.retire(
      overhang: 700, enteringEstimate: 210, at: 5, segments: &segments, liveSlots: &live)
    #expect(result.hypothesis == "all live thinking left")
    #expect(result.tokens == 900)
    #expect(result.count == 2)
    // The room a real set frees is not an overshoot.
    #expect(result.overshoot == 0)
    #expect(segments[0].deathCause == .inferred)
    #expect(segments[0].died == 5)
    #expect(segments[2].died == nil)
  }

  @Test("a set that does not fit what is entering is rejected")
  func setHypothesisRejected() {
    var (segments, live) = lane([(.think, 400), (.read, 3000), (.user, 200)])
    // Thinking is 400 against an overhang of 100, so the set would leave 300
    // for entering content the estimator puts at 4000. It does not fit.
    let result = LaneBuilder.retire(
      overhang: 100, enteringEstimate: 4000, at: 5, segments: &segments, liveSlots: &live)
    #expect(result.hypothesis == "best fitting set of older content")
  }

  @Test("the fallback takes thinking first and reports its overshoot")
  func fallbackOrder() {
    var (segments, live) = lane([(.read, 3000), (.think, 400), (.sys, 5000)])
    // Nothing is entering, so the room needed is the overhang alone. No
    // segment is that small, and the smallest one that covers it is taken.
    let result = LaneBuilder.retire(
      overhang: 100, enteringEstimate: 0, at: 5, segments: &segments, liveSlots: &live)
    #expect(result.hypothesis == "best fitting set of older content")
    #expect(result.count == 1)
    #expect(segments[1].died == 5)
    #expect(result.overshoot == 300)
  }

  @Test("the room freed is the room that is needed, not whatever is oldest")
  func aimsAtTheRoomNeeded() {
    var (segments, live) = lane([(.think, 10_016), (.read, 900), (.bash, 600), (.srch, 400)])
    // A large thinking block next to an overhang of 639 and a small input
    // entering. Taking the oldest first would free 10,016 tokens and hand
    // the surplus to the input.
    let result = LaneBuilder.retire(
      overhang: 639, enteringEstimate: 830, at: 9, segments: &segments, liveSlots: &live)
    #expect(result.tokens == 1300)
    #expect(result.overshoot == 0)
    #expect(result.absorbsSurplus)
    #expect(segments[0].died == nil)
  }

  @Test("the prefix is the last thing given up")
  func prefixGoesLast() {
    var (segments, live) = lane([(.sys, 5000), (.read, 100), (.bash, 100)])
    let result = LaneBuilder.retire(
      overhang: 150, enteringEstimate: 9000, at: 5, segments: &segments, liveSlots: &live)
    #expect(result.count == 2)
    #expect(segments[0].died == nil)
    #expect(segments[1].died == 5)
    #expect(segments[2].died == 5)
  }

  @Test("a death carries the confidence of the claim")
  func causesAreGraded() {
    #expect(DeathCause.chain.grade == .derived)
    #expect(DeathCause.compaction.grade == .derived)
    #expect(DeathCause.inferred.grade == .estimated)
  }

  @Test("a real lane records what it had to infer")
  func realLane() throws {
    let lane = try AdapterTests.lane("compaction-session").lane
    #expect(Validator.run(lane).mismatches.isEmpty)
    // Whatever was inferred is reported rather than hidden.
    let inferred = lane.segments.filter { $0.deathCause == .inferred }
    #expect(inferred.count == lane.stats.inferredRetirements)
    #expect(
      lane.events.filter { $0.kind == .inferredRetirement }.count
        == (lane.stats.inferredRetirements > 0 ? 1 : 0))
    // Everything the compaction dropped is attributed to the compaction.
    if let event = lane.compactions.first {
      #expect(lane.segments.contains { $0.died == event.atRequest })
    }
  }
}
