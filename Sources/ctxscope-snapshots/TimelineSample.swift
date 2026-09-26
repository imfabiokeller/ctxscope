import Foundation
import ScopeCore
import ScopeUI

/// The Timeline page filled with sample values: 87 bars of six parts each,
/// costs scaled to $3.94, prompt 7 selected, and three cache break cards.
///
/// Each kind's part is split into a few blocks, because the page draws every
/// block as its own slice, with a rule between two.
enum TimelineSample {
  /// First and last request, what was typed, and the largest addition
  /// with its size.
  private static let prompts: [(Int, Int, String, String, String)] = [
    (1, 5, "Read the API client and map how retries work", "Read · src/api/client.ts", "12.4k"),
    (6, 14, "Refactor retries into a single policy object", "Read · src/api/transport.ts", "5.2k"),
    (15, 22, "Run the tests and fix the failures", "Read · src/api/retry.ts", "8.1k"),
    (23, 30, "Update CLAUDE.md with the new retry rules", "Bash · npm test", "6.0k"),
    (31, 41, "Add jitter and a cap on total elapsed time", "Grep · \"jitter\"", "3.9k"),
    (42, 54, "Write tests for the elapsed-time cap", "WebFetch · MDN Math.random", "4.8k"),
    (55, 63, "Why is test_backoff flaky?", "Bash · npm test, full output", "14.2k"),
    (64, 75, "Connect GitHub and open a pull request", "GitHub MCP · 26 tool definitions", "9.8k"),
    (76, 87, "Address the review comments", "Bash · git diff", "6.3k"),
  ]
  private static let breakAt = [23: 1, 42: 2, 64: 3]
  private static let requests = 87
  private static let selected = 6
  /// How each kind's part is split into blocks, bottom first.
  private static let split = [0.5, 0.3, 0.2]

  static func data() -> TimelineData {
    let parts = (1...requests).map(parts(at:))
    let context = [15_400.0] + parts.map { $0.reduce(0, +) }
    var costs = [0.0]
    for request in 1...requests {
      let total = context[request]
      costs.append(
        total * 0.3e-6 + 1600 * 3.75e-6 + 0.002 + (breakAt[request] != nil ? total * 3.45e-6 : 0))
    }
    let factor = 3.94 / costs.reduce(0, +)
    costs = costs.map { $0 * factor }
    let rows = prompts.enumerated().map { index, prompt in
      row(index, prompt, context: context, costs: costs)
    }
    return TimelineData(
      headerNote: "87 requests · $3.94",
      chart: chart(parts: parts, costs: costs),
      prompts: rows,
      breaks: BreakList(count: "3", extra: "+$0.83", suffix: "this session", cards: cards),
      detail: detail(rows[selected], context: context, costs: costs))
  }

  /// The six parts of one request, in reading order.
  private static func parts(at request: Int) -> [Double] {
    let share = Double(request) / Double(requests)
    let jitter = Double((request * 37) % 11) / 11
    let prompt = prompts.firstIndex { request >= $0.0 && request <= $0.1 } ?? 8
    return [
      3100, request >= 64 ? 18400 : 8600, request >= 23 ? 4200 : 3700,
      6800 * Double(prompt + 1) / 9, 21300 * share,
      88800 * pow(share, 1.25) * (0.95 + 0.05 * jitter),
    ]
  }

  private static func chart(parts: [[Double]], costs: [Double]) -> TimelineChart {
    let blocks = Kind.allCases.flatMap { kind in
      split.indices.map { part in
        TimelineChart.Block(label: "\(kind.rawValue) \(part + 1)", kind: kind, size: "")
      }
    }
    let columns = parts.enumerated().map { index, sizes in
      var slices: [TimelineChart.Slice] = []
      var start = 0.0
      for (kind, size) in sizes.enumerated() {
        for (part, share) in split.enumerated() {
          let tokens = size * share
          slices.append(
            TimelineChart.Slice(
              block: kind * split.count + part, start: Int(start.rounded()),
              tokens: Int((start + tokens).rounded()) - Int(start.rounded())))
          start += tokens
        }
      }
      return TimelineChart.Column(slices: slices, title: "Request \(index + 1)", figures: "")
    }
    let dearest = costs.dropFirst().max() ?? 1
    let selectedRange = prompts[selected]
    return TimelineChart(
      identity: 87,
      scale: 200_000,
      blocks: blocks,
      columns: columns,
      breaks: breakAt.map { TimelineChart.Break(column: $0.key - 1, number: $0.value) }
        .sorted { $0.number < $1.number },
      costs: (1...requests).map {
        TimelineChart.Cost(share: costs[$0] / dearest, isBreak: breakAt[$0] != nil)
      },
      tokenTicks: TimelineChart.tokenTicks(200_000),
      requestTicks: TimelineChart.requestTicks(requests),
      highlighted: (selectedRange.0 - 1)...(selectedRange.1 - 1))
  }

  private static func row(
    _ index: Int, _ prompt: (Int, Int, String, String, String), context: [Double], costs: [Double]
  ) -> PromptRow {
    let sum = cost(of: prompt, costs)
    let breaks = breakAt.keys.count { $0 >= prompt.0 && $0 <= prompt.1 }
    return PromptRow(
      id: index + 1, requests: (prompt.0 - 1)...(prompt.1 - 1), isSelected: index == selected,
      number: "\(index + 1)", prompt: prompt.2, range: "\(prompt.0)\u{2013}\(prompt.1)",
      added: "+" + thousands(context[prompt.1] - context[prompt.0 - 1]), cost: money(sum),
      breaks: "\(breaks)")
  }

  private static func cost(of prompt: (Int, Int, String, String, String), _ costs: [Double])
    -> Double
  {
    (prompt.0...prompt.1).reduce(0) { $0 + costs[$1] }
  }

  private static func detail(_ row: PromptRow, context: [Double], costs: [Double]) -> PromptDetail {
    let prompt = prompts[selected]
    let count = prompt.1 - prompt.0 + 1
    let from = thousands(context[prompt.0 - 1])
    let to = thousands(context[prompt.1])
    return PromptDetail(
      number: row.number, requests: "requests \(row.range)",
      prompt: prompt.2,
      facts: [
        FactData("Context", row.added, detail: "\(from) \u{2192} \(to)"),
        FactData("Cost", row.cost, detail: "\(count) requests"),
        FactData("Per request", money(cost(of: prompt, costs) / Double(count))),
        FactData("Cache breaks", row.breaks),
        FactData(
          "Largest addition", prompt.3, swatch: FactData.Swatch(.results), trailing: prompt.4,
          wide: true),
      ],
      link: "Show context at request \(prompt.1)",
      linkRequest: prompt.1 - 1)
  }

  private static let cards = [
    BreakCard(
      id: 1, place: "Request 23 · prompt 4", extra: "+$0.17", title: "Memory changed",
      detail:
        "CLAUDE.md was edited, so everything after the system prompt and tools was sent uncached."
    ),
    BreakCard(
      id: 2, place: "Request 42 · prompt 6", extra: "+$0.27", title: "Cache expired",
      detail:
        "6 minutes passed since request 41, longer than the cache lasts. "
        + "The whole context was sent uncached."),
    BreakCard(
      id: 3, place: "Request 64 · prompt 8", extra: "+$0.39", title: "Tool definitions changed",
      detail:
        "The GitHub MCP server connected and added 26 tools (9.8k). "
        + "Everything after the tools was sent uncached."),
  ]

  /// "12.3k": thousands to one place.
  private static func thousands(_ value: Double) -> String {
    String(format: "%.1fk", value / 1000)
  }

  private static func money(_ value: Double) -> String {
    String(format: "$%.2f", value)
  }
}
