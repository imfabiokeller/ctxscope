import Testing

@testable import ScopeCore

/// A tool definition is judged by whether its tool was called. That is a yes
/// or a no, so it does not belong in a ratio of reused words.
@Suite("what counts towards the reused ratio")
struct ReuseRatioTests {
  static func lane(toolTokens: Int) -> Lane {
    var segments: [Segment] = []
    func add(_ band: Band, _ tokens: Int) {
      segments.append(
        Segment(
          id: SegmentID(segments.count), band: band, label: BandRegistry.label(of: band),
          tokens: Tokens(tokens, .estimated), characters: 100, contentClass: .prose, born: 0,
          contentHash: UInt64(segments.count)))
    }
    add(.user, 1000)
    add(.tools, toolTokens)
    return Lane(
      id: .main, window: .given(200_000), segments: segments,
      snapshots: [
        Snapshot(
          index: 0, requestID: "r0", timestamp: 0, model: "m",
          usage: RequestUsage(
            inputTokens: 1000 + toolTokens, cacheReadTokens: 0, cacheCreationTokens: 0,
            outputTokens: 0, thinkingTokens: 0, ephemeral1hTokens: 0, ephemeral5mTokens: 0))
      ])
  }

  static func report(_ lane: Lane, toolShare: Double) -> ReferenceReport {
    ReferenceReport(
      method: LexicalJudge().method,
      findings: [
        ReferenceFinding(
          segment: lane.segments[0].id, isAssessable: true, referencedShare: 0.1,
          referenceRequests: [0], matchedCounts: [1], assessedShingles: 10),
        ReferenceFinding(
          segment: lane.segments[1].id, isAssessable: true, referencedShare: toolShare,
          referenceRequests: toolShare > 0 ? [0] : [], matchedCounts: [1],
          assessedShingles: 1),
      ])
  }

  /// A called tool is a whole block at 100 percent. Left in the ratio it
  /// swamps the words.
  @Test("a called tool does not move the reused ratio")
  func calledToolIsNotInTheRatio() {
    let lane = Self.lane(toolTokens: 9000)
    let called = ReferenceAnalyzer.run(lane, references: Self.report(lane, toolShare: 1), at: 0)
    let idle = ReferenceAnalyzer.run(lane, references: Self.report(lane, toolShare: 0), at: 0)
    #expect(called.ratio == idle.ratio)
    #expect(called.inputRatio == idle.inputRatio)
    #expect(abs(called.ratio - 0.1) < 0.0001)
    // The tokens are still in the context, counted where they cannot be
    // assessed as words.
    #expect(called.totalTokens.value == 10_000)
    #expect(called.notAssessableTokens.value == 9000)
  }

  @Test("the rule names the two bands and nothing else")
  func onlyToolBands() {
    for band in Band.allCases {
      #expect(
        BandRegistry.countsTowardsReuseRatio(band) == (band != .tools && band != .mcp))
    }
  }
}
