import Testing

@testable import ScopeCore

/// Analyzers are pure functions of a recording, so the golden fixture here is
/// the seeded synthetic recording: same seed, same numbers, every run.
@Suite("Analyzers")
struct AnalyzerTests {
  private var lane: Lane {
    SyntheticRecording.make().mainLane!
  }

  @Test("the tally sums to the measured total at every request")
  func tallyIsExact() {
    let tally = TallyAnalyzer.run(lane)
    #expect(tally.perRequest.count == lane.snapshots.count)
    for entry in tally.perRequest {
      #expect(entry.byBand.reduce(0) { $0 + $1.value } == entry.total.value)
      #expect(entry.total.grade == .measured)
    }
  }

  @Test("the prefix is there from the first request and never leaves")
  func prefixPersists() {
    let tally = TallyAnalyzer.run(lane)
    let first = tally.perRequest[0].byBand[BandRegistry.position(of: .sys)]
    let last = tally.perRequest[tally.perRequest.count - 1]
      .byBand[BandRegistry.position(of: .sys)]
    #expect(first.value > 0)
    #expect(first.value == last.value)
  }

  @Test("what another session of the same model held raises the bound")
  func windowHints() {
    let snapshots = [
      Snapshot(
        index: 0, requestID: nil, timestamp: 0, model: "m",
        usage: RequestUsage(cacheReadTokens: 150_000))
    ]
    var hints = ModelWindowHints()
    hints.observe(model: "m", peak: 790_000)
    let hinted = WindowEstimate(observing: snapshots, [], hints: hints)
    #expect(hinted.tokens == 1_000_000)
    // The bound rests on a flag another session was started with, not on this
    // one's own arithmetic.
    #expect(hinted.grade == .estimated)
    #expect(hinted.observedPeak == 150_000)

    // A hint for another model says nothing about this one.
    var other = ModelWindowHints()
    other.observe(model: "n", peak: 790_000)
    #expect(WindowEstimate(observing: snapshots, [], hints: other).tokens == 200_000)
  }

  @Test("the window is inferred as the smallest one that fits")
  func window() {
    let small = WindowEstimate(
      observing: [
        Snapshot(
          index: 0, requestID: nil, timestamp: 0, model: "m",
          usage: RequestUsage(cacheReadTokens: 150_000))
      ], [])
    #expect(small.tokens == 200_000)
    #expect(small.grade == .derived)
    #expect(small.isLowerBound)
    #expect(small.label.hasPrefix("at least"))

    let large = WindowEstimate(
      observing: [
        Snapshot(
          index: 0, requestID: nil, timestamp: 0, model: "m",
          usage: RequestUsage(cacheReadTokens: 900_000))
      ], [])
    #expect(large.tokens == 1_000_000)
    // A compaction is a measured statement about where the harness compacts.
    let compacted = WindowEstimate(
      observing: [
        Snapshot(
          index: 0, requestID: nil, timestamp: 0, model: "m",
          usage: RequestUsage(cacheReadTokens: 400_000))
      ],
      [
        CompactionEvent(
          atRequest: 1, trigger: "auto", preTokens: 999_274, postTokens: 18_020,
          droppedTokens: 981_254)
      ])
    #expect(compacted.tokens == 1_000_000)
    #expect(compacted.autoCompactTokens == Tokens(999_274, .measured))
  }

  @Test("fill is never reported above the window")
  func fillIsClamped() {
    let window = WindowEstimate.given(200_000)
    #expect(window.fill(400_000) == 1)
    #expect(window.fill(100_000) == 0.5)
  }

  @Test("cache hit and busts come out of measured usage only")
  func cache() {
    let analysis = CacheAnalyzer.run(lane)
    #expect(analysis.perRequest.count == lane.snapshots.count)
    #expect(analysis.perRequest.allSatisfy { $0.readTokens.grade == .measured })
    #expect(analysis.totalRead.value > 0)
    #expect(analysis.totalRead.grade == .measured)
    // The synthetic lane busts its cache once and compacts once.
    #expect(!analysis.busts.isEmpty)
    #expect(analysis.busts.allSatisfy { $0.rewrittenTokens.grade == .derived })
  }

  @Test("every bust says what caused it")
  func bustCauses() {
    let analysis = CacheAnalyzer.run(lane)
    #expect(analysis.busts.allSatisfy { CacheBustCause.allCases.contains($0.cause) })
    // The compaction of the synthetic lane is named as one.
    let compaction = lane.compactions.first?.atRequest
    if let compaction {
      #expect(analysis.busts.first { $0.request == compaction }?.cause == .compaction)
    }
  }

  @Test("a bust is compared against the request it continued from")
  func bustUsesTheParentRequest() {
    let usage = RequestUsage(cacheReadTokens: 1000, cacheCreationTokens: 100)
    let rewound = RequestUsage(cacheReadTokens: 200, cacheCreationTokens: 50)
    let lane = Lane(
      id: .main,
      window: .given(200_000),
      segments: [],
      snapshots: [
        Snapshot(index: 0, requestID: nil, timestamp: 0, model: "m", usage: usage),
        Snapshot(index: 1, requestID: nil, timestamp: 1, model: "m", usage: usage),
        // Continues from request 0, not from request 1.
        Snapshot(
          index: 2, requestID: nil, timestamp: 2, model: "m", usage: rewound,
          parentRequest: 0),
      ])
    let analysis = CacheAnalyzer.run(lane)
    let bust = analysis.busts.first { $0.request == 2 }
    #expect(bust?.expectedReadTokens == 1100)
    #expect(bust?.cause == .rewind)
  }

  @Test("carry cost is tokens times requests carried")
  func carryCost() {
    let lane = self.lane
    let analysis = CarryCostAnalyzer.run(lane, references: nil)
    var expected = 0
    for segment in lane.segments {
      let died = min(segment.died ?? lane.snapshots.count, lane.snapshots.count)
      expected += segment.tokens.value * max(0, died - segment.born)
    }
    #expect(analysis.totalCarryTokens.value == expected)
    #expect(analysis.ranked.count == lane.segments.count)
  }

  @Test("the ranked list puts the biggest unreferenced cost first")
  func ranking() {
    let analysis = CarryCostAnalyzer.run(lane, references: nil)
    let assessable = analysis.ranked.filter { $0.unreferencedCarryTokens != nil }
    let costs = assessable.map { $0.unreferencedCarryTokens?.value ?? 0 }
    #expect(costs == costs.sorted(by: >))
    #expect(analysis.top(6).count == 6)
    // Segments nothing can be said about rank last, never as zero cost.
    #expect(analysis.ranked.suffix(4).allSatisfy { !$0.isAssessable })
  }

  @Test("duplication finds the file read twice")
  func duplication() {
    let analysis = DuplicationAnalyzer.run(lane)
    #expect(!analysis.groups.isEmpty)
    #expect(analysis.wastedCarryTokens.value > 0)
    for group in analysis.groups {
      #expect(group.segments.count > 1)
    }
  }

  @Test("compaction is measured, not inferred")
  func compaction() {
    let lane = self.lane
    #expect(lane.compactions.count == 1)
    let event = lane.compactions[0]
    #expect(event.preTokens > event.postTokens)
    #expect(event.droppedTokens == event.preTokens - event.postTokens)
  }

  @Test("the compaction analyzer says what survived and what went")
  func compactionAnalysis() throws {
    let lane = self.lane
    let analysis = CompactionAnalyzer.run(lane)
    #expect(analysis.count == 1)
    let summary = try #require(analysis.compactions.first)
    #expect(summary.survivingSegments > 0)
    #expect(summary.droppedSegments > 0)
    #expect(summary.droppedTokens.value > 0)
    // The synthetic lane is built to be exact, so the harness number and the
    // reconstruction agree.
    #expect(summary.disagreement == 0)
  }

  @Test("validation passes on a recording built to be exact")
  func validation() {
    let result = Validator.run(lane)
    #expect(result.passed)
    #expect(result.mismatches.isEmpty)
  }

  @Test("a million token window analyzes in well under two seconds")
  func scale() {
    let start = ContinuousClock.now
    let lane = SyntheticRecording.make(.millionTokenWindow).mainLane!
    #expect(lane.snapshots.map(\.usage.promptTotal).max()! > 700_000)
    let tally = TallyAnalyzer.run(lane)
    #expect(
      tally.perRequest.allSatisfy { $0.byBand.reduce(0) { $0 + $1.value } == $0.total.value })
    #expect(Validator.run(lane).passed)
    #expect(CarryCostAnalyzer.run(lane, references: nil).maxUnreferencedAge > 300)
    _ = SegmentCacheAnalyzer.run(lane)
    _ = DuplicationAnalyzer.run(lane)
    _ = CompactionAnalyzer.run(lane)
    // The bar for a 1M window, measured rather than assumed. Generous
    // against the 25 ms this actually takes, because a test machine under
    // load is still a machine that has to pass.
    let elapsed = ContinuousClock.now - start
    #expect(elapsed < .seconds(2))
  }

  @Test("carry cost stays linear as requests grow")
  func scaleIsLinear() {
    func time(_ requests: Int) -> Double {
      var options = SyntheticRecording.Options.millionTokenWindow
      options.requests = requests
      let lane = SyntheticRecording.make(options).mainLane!
      let start = ContinuousClock.now
      _ = DuplicationAnalyzer.run(lane)
      _ = CarryCostAnalyzer.run(lane, references: nil)
      _ = TallyAnalyzer.run(lane)
      return Double((ContinuousClock.now - start).components.attoseconds) / 1e18
    }
    let small = time(500)
    let large = time(4000)
    // Eight times the requests must not cost anywhere near sixty four times
    // the work, which is what the quadratic version did.
    #expect(large < max(small * 40, 0.5))
  }
}
