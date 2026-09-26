import Testing

@testable import ScopeCore

/// The bands held against the harness's own
/// `/context` report, with the error per category.
@Suite("the harness comparison")
struct HarnessCheckTests {
  static func lane(report: ContextReport?, prefix: Int, rest: Int) -> Lane {
    var segments: [Segment] = []
    func add(_ band: Band, _ tokens: Int) {
      segments.append(
        Segment(
          id: SegmentID(segments.count), band: band, label: BandRegistry.label(of: band),
          tokens: Tokens(tokens, .estimated), characters: 0, contentClass: .prose, born: 0,
          contentHash: UInt64(segments.count)))
    }
    add(.sys, prefix / 4)
    add(.tools, prefix / 4)
    add(.mcp, prefix / 4)
    add(.mem, prefix - 3 * (prefix / 4))
    add(.user, rest)
    let usage = RequestUsage(
      inputTokens: prefix + rest, cacheReadTokens: 0, cacheCreationTokens: 0,
      outputTokens: 0, thinkingTokens: 0, ephemeral1hTokens: 0, ephemeral5mTokens: 0)
    return Lane(
      id: .main, window: .given(200_000), segments: segments,
      snapshots: [
        Snapshot(index: 0, requestID: "r0", timestamp: 0, model: "m", usage: usage)
      ],
      contextReport: report)
  }

  static func report(prefix: Int, rest: Int) -> ContextReport {
    ContextReport(
      systemPrompt: prefix / 4, systemTools: prefix / 4, mcpTools: prefix / 4,
      memoryFiles: prefix - 3 * (prefix / 4), skills: 0, messages: rest,
      total: prefix + rest)
  }

  @Test("a lane with no report is not compared")
  func noReport() {
    let checks = Validator.run(Self.lane(report: nil, prefix: 40_000, rest: 60_000)).checks
    #expect(!checks.contains { $0.name.contains("harness") })
  }

  @Test("the comparison names every category and its error")
  func comparesEachBand() throws {
    let lane = Self.lane(
      report: Self.report(prefix: 40_000, rest: 60_000), prefix: 40_000, rest: 60_000)
    let check = try #require(Validator.run(lane).checks.first { $0.name.contains("harness") })
    #expect(check.passed)
    for band in ["sys", "tools", "mcp", "mem", "the rest", "total"] {
      #expect(check.detail.contains(band))
    }
    #expect(check.detail.contains("request 1"))
    #expect(check.detail.contains("0%"))
  }

  /// A report that describes a different session is not a failure of the
  /// estimator, it is a report that does not belong to this lane, and the
  /// check says so rather than passing quietly.
  @Test("a report that cannot be about this lane fails the check")
  func mismatchedReport() throws {
    let lane = Self.lane(
      report: Self.report(prefix: 40_000, rest: 600_000), prefix: 40_000, rest: 60_000)
    let check = try #require(Validator.run(lane).checks.first { $0.name.contains("harness") })
    #expect(!check.passed)
  }
}
