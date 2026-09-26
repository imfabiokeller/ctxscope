import Foundation
import ScopeCore
import ScopeUI
import SwiftUI

struct ContextSample: View {
  var body: some View {
    ContextWindow {
      ContextMain(
        data: Self.data, filter: .constant(.all), query: .constant(""),
        selection: .constant(Self.rows[0].id))
    } sidebar: {
      ContextSidebar(
        inspector: Self.data.inspector, noSelection: ContextPresenter.noSelection,
        onShowInTimeline: { _ in }, onCopy: { _ in })
    }
  }

  // Thousandths of a token, so the fractional sample sizes place every slice exactly.
  private static let unit = 1000

  static let data = ContextPageData(
    cards: [
      SummaryCardData(
        label: "Context", figure: "142.6k", unit: "of 200k",
        detail: "71% full · +3.7k this request"),
      SummaryCardData(
        label: "This request", figure: "$0.058",
        detail: "138.9k read from cache · 3.7k written"),
      SummaryCardData(
        label: "Session so far", figure: "$3.94",
        detail: "87 requests · 9 prompts · 3 cache breaks"),
      SummaryCardData(
        label: "Carried, unused", figure: "61.2k", detail: "43% of context · $1.12 so far"),
    ],
    strip: StripData(
      title: "Context in reading order", scaleNote: "0 → 200k tokens", scale: 200_000 * unit,
      slices: slices,
      prefix: StripMark(at: 25_700 * unit, label: "sent with every request · 25.7k"),
      cache: StripMark(at: 138_900 * unit, label: "cached up to here · 138.9k"),
      selected: selected, request: "Request 87", figures: "142.6k · $0.058"),
    legend: [
      LegendEntryData(kind: .system, name: "system", detail: "3.1k · 2%"),
      LegendEntryData(kind: .tools, name: "tools", detail: "18.4k · 13%"),
      LegendEntryData(kind: .memory, name: "memory", detail: "4.2k · 3%"),
      LegendEntryData(kind: .you, name: "you", detail: "6.8k · 5%"),
      LegendEntryData(kind: .agent, name: "agent", detail: "21.3k · 15%"),
      LegendEntryData(kind: .results, name: "results", detail: "88.8k · 62%"),
    ],
    blocks: ContextPresenter.blocks(count: 1284, rows: rows),
    inspector: InspectorData(
      block: SegmentID(0), kind: .results, kindName: "results",
      title: "Bash · npm test (full output)",
      facts: [
        FactData("Size", "~14,236", detail: "tokens, estimated"),
        FactData("Carried", "32", detail: "requests"),
        FactData("Cost so far", "$0.14", detail: "$0.0043 per request"),
        FactData("Added in", "Request 56", detail: "prompt 7"),
        FactData("Used", "No", detail: "no later text reuses it", wide: true),
        FactData("Came from", "Tool result of Bash: npm test", wide: true),
      ],
      textTitle: "Text", text: testOutput, timelineTitle: "Show in timeline",
      copyTitle: "Copy text"),
    noSelection: ContextPresenter.noSelection)

  private typealias SampleBlock = (
    kind: Kind, label: String, tokens: Int, requestsCarried: Int, used: Bool?
  )
  private static let blocks: [SampleBlock] = [
    (.results, "Bash · npm test (full output)", 14_236, 32, false),
    (.results, "Read · src/api/client.ts", 12_380, 31, true),
    (.tools, "GitHub MCP · 26 tool definitions", 9804, 24, nil),
    (.results, "Read · src/api/retry.ts", 8110, 72, true),
    (.tools, "Built-in tools · 18 definitions", 7920, 87, nil),
    (.results, "Grep · \"backoff\" (212 matches)", 7640, 28, false),
    (.results, "Bash · git diff", 6310, 11, true),
    (.results, "Read · tests/test_backoff.ts", 5920, 33, true),
    (.results, "WebFetch · MDN Math.random", 4810, 40, false),
    (.agent, "Thinking · plan for the jitter cap", 4390, 46, false),
    (.memory, "CLAUDE.md", 3640, 65, nil),
    (.system, "System prompt", 3100, 87, nil),
  ]

  static let rows: [BlockRowData] = blocks.enumerated().map { index, block in
    let (kind, label, tokens, carried, used) = block
    return BlockRowData(
      id: SegmentID(index), members: [SegmentID(index)], kind: kind, kindName: kind.rawValue,
      label: label, size: "~" + TokenFormat.short(tokens), carried: "\(carried) req",
      used: used.map { $0 ? "yes" : "no" } ?? "not tracked",
      use: used.map { $0 ? .used : .unused } ?? .notTracked,
      cost: TokenFormat.cents(Double(tokens * carried) * 0.3e-6))
  }

  private static let slices: [StripSlice] = {
    let phases = [
      (1, 5), (6, 14), (15, 22), (23, 30), (31, 41), (42, 54), (55, 63), (64, 75), (76, 87),
    ]
    var parts: [(Kind, Double)] = [
      (.system, 3100), (.tools, 8600), (.tools, 9800), (.memory, 4200),
    ]
    for (first, last) in phases {
      let requests = Double(last - first + 1)
      let results = 88_800 * requests / 87
      let agent = 21_300 * requests / 87
      parts += [
        (.you, 6800.0 / 9), (.agent, agent * 0.4), (.results, results * 0.45),
        (.agent, agent * 0.3), (.results, results * 0.35), (.agent, agent * 0.3),
        (.results, results * 0.2),
      ]
    }
    var start = 0
    return parts.enumerated().map { index, part in
      let tokens = Int((part.1 * Double(unit)).rounded())
      defer { start += tokens }
      return StripSlice(
        id: SegmentID(1000 + index), start: start, tokens: tokens, grade: .estimated,
        kind: part.0, label: part.0.rawValue)
    }
  }()

  // Zero-based: request 55 here is request 56 on the page.
  private static let selected: Range<Int> = {
    let phases = [5, 14, 22, 30, 41, 54, 63, 75, 87]
    let request = 55.0
    let phase = Double((phases.firstIndex { Int(request) <= $0 } ?? 8) + 1)
    let fraction = request / 87
    let before = 88_800 * pow(fraction, 1.25) + 21_300 * fraction + 6800 * phase / 9
    let start = Int(((25_700 + before) * Double(unit)).rounded())
    return start..<(start + 14_236 * unit)
  }()

  private static let testOutput = """
    > api-client@2.4.0 test
    > jest --runInBand

    PASS  tests/test_policy.ts
    PASS  tests/test_client.ts
    FAIL  tests/test_backoff.ts
      ● backoff › caps elapsed time
        expect(received).toBeLessThanOrEqual(expected)
        Expected: <= 30000
        Received:    30412

    Tests: 1 failed, 214 passed, 215 total
    …
    """
}
