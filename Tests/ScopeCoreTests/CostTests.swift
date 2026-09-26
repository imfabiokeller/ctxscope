import Testing

@testable import ScopeCore

@Suite("Cost")
struct CostTests {
  private static func lane(_ usages: [RequestUsage], models: [String]? = nil) -> Lane {
    Lane(
      id: .main,
      window: .given(200_000),
      segments: [],
      snapshots: usages.enumerated().map { index, usage in
        Snapshot(
          index: index, requestID: nil, timestamp: Double(index) * 10,
          model: models?[index] ?? "m", usage: usage)
      })
  }

  @Test("a request costs its own counts times the brief's prices")
  func oneRequest() {
    let usage = RequestUsage(
      inputTokens: 1000, cacheReadTokens: 100_000, cacheCreationTokens: 4000,
      outputTokens: 2000)
    let cost = CostAnalyzer.run(Self.lane([usage]))
    let request = cost.perRequest[0]
    // 100k at 0.25, 4k at 20, 1k at 10, per million.
    #expect(abs(request.context - (0.025 + 0.08 + 0.01)) < 1e-12)
    #expect(abs(request.output - 0.1) < 1e-12)
    #expect(abs(request.total - 0.215) < 1e-12)
    #expect(request.contextTokens == 105_000)
    #expect(abs(request.readAgain - 0.02625) < 1e-12)
    #expect(abs(request.sentAgain - 2.1) < 1e-12)
    #expect(cost.context(through: 0) == request.context)
    #expect(cost.context(through: 7) == request.context)
  }

  @Test("an empty lane costs nothing and answers every question with zero")
  func empty() {
    let cost = CostAnalyzer.run(Self.lane([]))
    #expect(cost.perRequest.isEmpty)
    #expect(cost.context(through: 3) == 0)
    #expect(cost.total(through: 0) == 0)
    #expect(cost.context(in: 0...4) == 0)
  }

  @Test("the session so far is the running sum, and a range is a difference of two")
  func cumulative() {
    let lane = SyntheticRecording.make().mainLane!
    let cost = CostAnalyzer.run(lane)
    var running = 0.0
    for (index, request) in cost.perRequest.enumerated() {
      running += request.context
      #expect(abs(cost.context(through: index) - running) < 1e-9)
    }
    let middle = cost.perRequest[5...9].reduce(0) { $0 + $1.context }
    #expect(abs(cost.context(in: 5...9) - middle) < 1e-9)
    #expect(abs(cost.context(in: 0...9) - cost.context(through: 9)) < 1e-9)
    #expect(cost.total(through: 20) > cost.context(through: 20))
  }

  @Test("a cache break adds the rewritten tokens at write minus read")
  func breakExtra() {
    let lane = SyntheticRecording.make().mainLane!
    let cost = CostAnalyzer.run(lane)
    let busts = CacheAnalyzer.run(lane).busts
    #expect(!busts.isEmpty)
    for bust in busts {
      let expected = Double(bust.rewrittenTokens.value) * (20 - 0.25) / 1_000_000
      #expect(abs(cost.extra(of: bust) - expected) < 1e-12)
    }
  }

  @Test("the longest matching prefix decides a model's prices")
  func priceTable() {
    let cheap = Prices(cacheWrite: 2, cacheRead: 0.1, input: 1, output: 5)
    let narrow = Prices(cacheWrite: 4, cacheRead: 0.2, input: 2, output: 10)
    let table = PriceTable(
      entries: [
        PriceTable.Entry(modelPrefix: "claude-x-1", prices: narrow),
        PriceTable.Entry(modelPrefix: "claude-x", prices: cheap),
      ],
      fallback: PriceTable.standard.fallback)
    #expect(table.prices(for: "claude-x-1-20260101") == narrow)
    #expect(table.prices(for: "claude-x-2") == cheap)
    #expect(table.prices(for: "other") == PriceTable.standard.fallback)

    let usage = RequestUsage(cacheReadTokens: 1_000_000)
    let cost = CostAnalyzer.run(
      Self.lane([usage, usage], models: ["claude-x-2", "other"]), prices: table)
    #expect(cost.perRequest[0].context == 0.1)
    #expect(cost.perRequest[1].context == 0.25)
  }
}
