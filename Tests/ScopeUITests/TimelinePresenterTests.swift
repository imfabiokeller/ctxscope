import Foundation
import ScopeCore
import Testing

@testable import ScopeUI

@Suite("Timeline presenter")
struct TimelinePresenterTests {
  @Test("the synthetic 200k lane: every request a column, every block a slice")
  func synthetic() throws {
    let lane = SyntheticRecording.make().lanes[0]
    let data = TimelineLanes.present(lane, selected: 3)
    let chart = data.chart
    #expect(chart.columns.count == lane.requestCount)
    #expect(data.headerNote.hasPrefix("\(lane.requestCount) requests · $"))
    let order = ReadingOrder(lane)
    for request in [0, 20, lane.requestCount - 1] {
      let column = order.column(at: request)
      #expect(chart.columns[request].slices.count == column.slices.count)
      #expect(chart.columns[request].end == column.end)
      #expect(chart.columns[request].title == "Request \(request + 1)")
    }
    #expect(chart.scale == 200_000)
    #expect(chart.tokenTicks.map(\.label) == ["0", "50k", "100k", "150k", "200k"])
    let cache = CacheAnalyzer.run(lane)
    #expect(chart.breaks.map(\.column) == cache.busts.map(\.request))
    #expect(data.breaks.cards.count == cache.busts.count)
    #expect(chart.costs.contains { $0.share == 1 })
    #expect(chart.costs.allSatisfy { $0.share >= 0 && $0.share <= 1 })
  }

  @Test("the selected prompt dims the others and fills the detail")
  func selection() throws {
    let lane = TimelineLanes.lane(requests: 9, prompts: [0, 3, 6])
    let data = TimelineLanes.present(lane, selected: 2)
    #expect(data.chart.highlighted == 3...5)
    #expect(data.chart.isHighlighted(4))
    #expect(!data.chart.isHighlighted(6))
    #expect(data.prompts.map(\.range) == ["1\u{2013}3", "4\u{2013}6", "7\u{2013}9"])
    #expect(data.prompts.map(\.isSelected) == [false, true, false])
    let detail = try #require(data.detail)
    #expect(detail.number == "2")
    #expect(detail.requests == "requests 4\u{2013}6")
    #expect(detail.prompt == "Prompt at 3")
    #expect(detail.link == "Show context at request 6")
    #expect(detail.linkRequest == 5)
    #expect(
      detail.facts.map(\.term) == [
        "Context", "Cost", "Per request", "Cache breaks", "Largest addition",
      ])
    #expect(detail.facts[0].value == "+3.2k")
    #expect(detail.facts[0].detail == "16.2k \u{2192} 19.4k")
    #expect(detail.facts[1].detail == "3 requests")
    #expect(detail.facts[3].value == "0")
    #expect(detail.facts[3].detail == nil)
    #expect(detail.facts[4].value == "file3.swift")
    #expect(detail.facts[4].trailing == "~1.0k")
    #expect(detail.facts[4].isWide)
    #expect(detail.facts[4].swatch != nil)
    #expect(detail.facts.prefix(4).allSatisfy { !$0.isWide })
  }

  @Test("a lane with no cache breaks has no marks and no cards")
  func noBreaks() {
    let data = TimelineLanes.present(TimelineLanes.lane(requests: 5), selected: 1)
    #expect(data.chart.breaks.isEmpty)
    #expect(data.breaks.cards.isEmpty)
    #expect(data.breaks.count == "0")
    #expect(data.breaks.extra == "+$0.00")
    #expect(data.prompts.map(\.breaks) == ["0"])
    #expect(data.chart.costs.allSatisfy { !$0.isBreak })
  }

  @Test("a lane with no prompts has no bands, no rows and no detail")
  func noPrompts() {
    let data = TimelineLanes.present(TimelineLanes.lane(requests: 4, prompts: []), selected: 1)
    #expect(data.prompts.isEmpty)
    #expect(data.detail == nil)
    #expect(data.chart.highlighted == nil)
    #expect(data.chart.columns.count == 4)
  }

  @Test("one request is one column and one number")
  func oneRequest() throws {
    let lane = try #require(SyntheticRecording.make(.oneRequest).mainLane)
    let data = TimelineLanes.present(lane)
    #expect(data.chart.columns.count == 1)
    #expect(data.chart.requestTicks.map(\.label) == ["request 1"])
    #expect(data.headerNote.hasPrefix("1 request · "))
    #expect(data.chart.costs.map(\.share) == [1])
  }

  @Test("many requests over a 1M window")
  func manyRequests() throws {
    let lane = try #require(SyntheticRecording.make(.millionTokenWindow).mainLane)
    let data = TimelineLanes.present(lane, selected: 5)
    #expect(data.chart.columns.count == 361)
    #expect(data.chart.tokenTicks.map(\.label) == ["0", "250k", "500k", "750k", "1M"])
    #expect(data.chart.requestTicks.map(\.label) == ["request 1", "100", "200", "300", "361"])
    #expect(data.chart.requestTicks.map(\.position) == [0, 99, 199, 299, 360])
  }

  @Test("request numbers are round, and none crowds the last")
  func requestTicks() {
    #expect(TimelineChart.requestTicks(87).map(\.label) == ["request 1", "20", "40", "60", "87"])
    #expect(
      TimelineChart.requestTicks(200).map(\.label) == ["request 1", "50", "100", "150", "200"])
    #expect(TimelineChart.requestTicks(2).map(\.label) == ["request 1", "2"])
    #expect(TimelineChart.requestTicks(0).isEmpty)
  }

  @Test("a slice is found by the tokens under the pointer")
  func sliceLookup() {
    let column = TimelineChart.Column(
      slices: [
        .init(block: 0, start: 0, tokens: 10), .init(block: 1, start: 10, tokens: 5),
        .init(block: 2, start: 15, tokens: 20),
      ], title: "", figures: "")
    #expect(column.slice(atTokens: 0) == 0)
    #expect(column.slice(atTokens: 9) == 0)
    #expect(column.slice(atTokens: 10) == 1)
    #expect(column.slice(atTokens: 34) == 2)
    #expect(column.slice(atTokens: 35) == nil)
    #expect(column.slice(atTokens: -1) == nil)
  }
}
