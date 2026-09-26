import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture
@testable import ScopeUI

/// What the Context page says, checked without drawing it.
@Suite("Context presenter")
@MainActor
struct ContextPresenterTests {
  static func analysis(_ options: SyntheticRecording.Options = .init()) -> LaneAnalysis {
    let recording = SyntheticRecording.make(options)
    let lane = recording.mainLane ?? Lane(id: .main, window: .given(1), segments: [], snapshots: [])
    var judge = LexicalJudge()
    judge.add(ModelTests.judgeInput(recording))
    return LaneAnalysis(session: recording.sessionID, lane: lane, references: judge.report())
  }

  /// A sanitized fixture read the way the app reads a transcript.
  static func fixture(_ name: String) throws -> LaneAnalysis {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appending(path: "ScopeCaptureTests/Fixtures/\(name).jsonl")
    var builder = LaneBuilder(id: .main, agentType: nil, parentToolUseID: nil, window: nil)
    builder.append(try ClaudeCodeAdapter.entries(at: url))
    let output = builder.finish()
    var judge = LexicalJudge(segmentShingleCap: LaneBuilder.shingleCap)
    judge.add(output.judgeInput)
    return LaneAnalysis(session: name, lane: output.lane, references: judge.report())
  }

  @Test("the four cards carry the analyzers' own figures")
  func cards() throws {
    let analysis = Self.analysis()
    let figures = analysis.figures(at: analysis.lastRequest)
    let page = ContextPresenter.page(analysis, figures)
    #expect(
      page.cards.map(\.label) == ["Context", "This request", "Session so far", "Carried, unused"])
    let total = try #require(figures.tally).total.value
    #expect(page.cards[0].figure == TokenFormat.short(total))
    #expect(page.cards[0].unit == "of 200k")
    #expect(page.cards[0].detail.hasSuffix("this request"))
    #expect(page.cards[1].figure == TokenFormat.dollars(try #require(figures.cost).context))
    #expect(page.cards[1].detail.contains("read from cache"))
    #expect(
      page.cards[2].figure == TokenFormat.dollars(analysis.costs.context(through: figures.request)))
    #expect(page.cards[2].detail.hasPrefix("\(analysis.requestCount) requests · "))
    #expect(page.cards[3].figure == UIFormat.tokens(figures.unused.tokens))
    #expect(page.cards[3].detail.hasSuffix("so far"))
  }

  @Test("rows are largest first, sizes are marked estimated, and every block is on the strip")
  func rows() throws {
    let analysis = Self.analysis()
    let figures = analysis.figures(at: analysis.lastRequest)
    let page = ContextPresenter.page(analysis, figures)
    let sizes = page.blocks.rows.map { row in
      row.members.compactMap { analysis.segment($0)?.tokens.value }.reduce(0, +)
    }
    #expect(sizes == sizes.sorted(by: >))
    #expect(
      page.blocks.detail
        == "\(UIFormat.count(figures.column.slices.count)) in this request · largest first")
    #expect(page.blocks.rows.allSatisfy { $0.carried.hasSuffix(" req") && $0.cost.hasPrefix("$") })
    let estimated = page.blocks.rows.filter { row in
      row.members.count == 1 && analysis.segment(row.id)?.tokens.grade == .estimated
    }
    #expect(!estimated.isEmpty)
    #expect(estimated.allSatisfy { $0.size.hasPrefix("~") })
    #expect(page.strip.slices.count == figures.column.slices.count)
    #expect(page.strip.scale == 200_000)
    #expect(page.strip.prefix?.label.hasPrefix("sent with every request · ") == true)
    #expect(page.strip.cache?.label.hasPrefix("cached up to here · ") == true)
    #expect(
      page.legend.map(\.name).prefix(6) == ["system", "tools", "memory", "you", "agent", "results"])
  }

  @Test("the filters and the text filter leave only what they say")
  func filters() throws {
    let analysis = Self.analysis()
    let figures = analysis.figures(at: analysis.lastRequest)
    let all = ContextPresenter.page(analysis, figures).blocks.rows
    let unused = ContextPresenter.page(analysis, figures, filter: .unused).blocks.rows
    #expect(!unused.isEmpty && unused.count < all.count)
    #expect(unused.allSatisfy { $0.use == .unused && $0.used == "no" })
    let prefix = ContextPresenter.page(analysis, figures, filter: .everyRequest).blocks.rows
    #expect(!prefix.isEmpty)
    #expect(prefix.allSatisfy { [.system, .tools, .memory].contains($0.kind) })
    let label = try #require(all.first { $0.kind == .results }).label
    let found = ContextPresenter.page(analysis, figures, query: label.uppercased()).blocks.rows
    #expect(!found.isEmpty)
    #expect(found.allSatisfy { $0.label.localizedCaseInsensitiveContains(label) })
  }

  @Test("tool definitions are one row per server, with the group's words in the sidebar")
  func grouping() throws {
    let analysis = try Self.fixture("short-session")
    let figures = analysis.figures(at: analysis.lastRequest)
    let rows = ContextPresenter.page(analysis, figures).blocks.rows
    let tools = rows.filter { $0.kind == .tools }
    #expect(
      tools.contains { $0.label == "Built-in tools · 17 definitions" && $0.members.count == 17 })
    #expect(tools.contains { $0.label == "2d2179e129e4 MCP · 19 tool definitions" })
    #expect(tools.allSatisfy { $0.used == "not tracked" })
    let server = try #require(tools.first { $0.label.hasPrefix("2d2179e129e4") })
    let member = try #require(server.members.last)
    let page = ContextPresenter.page(analysis, figures, selection: member)
    let inspector = try #require(page.inspector)
    #expect(inspector.title == server.label)
    let facts = Dictionary(uniqueKeysWithValues: inspector.facts.map { ($0.term, $0.value) })
    #expect(facts["Came from"]?.hasPrefix("MCP server 2d2179e129e4, connected in request ") == true)
    #expect(facts["Used"] == "Not tracked")
    // The whole group is outlined on the strip, whichever member was picked.
    #expect(
      page.strip.selected?.count
        == server.members.compactMap { analysis.segment($0)?.tokens.value }.reduce(0, +))
  }

  @Test("the sidebar writes a block's facts in the brief's words")
  func inspector() throws {
    let analysis = Self.analysis()
    let figures = analysis.figures(at: analysis.lastRequest)
    let row = try #require(
      ContextPresenter.page(analysis, figures, filter: .unused).blocks.rows.first)
    let segment = try #require(analysis.segment(row.id))
    let page = ContextPresenter.page(analysis, figures, selection: row.id, text: "hello")
    let inspector = try #require(page.inspector)
    #expect(inspector.title == segment.label)
    #expect(inspector.text == "hello")
    #expect(
      inspector.facts.map(\.term) == [
        "Size", "Carried", "Cost so far", "Added in", "Used", "Came from",
      ])
    let facts = Dictionary(uniqueKeysWithValues: inspector.facts.map { ($0.term, $0) })
    #expect(facts["Size"]?.value == "~\(UIFormat.count(segment.tokens.value))")
    #expect(facts["Size"]?.detail == "tokens, estimated")
    #expect(facts["Used"]?.value == "No")
    #expect(facts["Used"]?.detail == "no later text reuses it")
    #expect(facts["Added in"]?.value == "Request \(segment.born + 1)")
    #expect(facts["Cost so far"]?.detail?.hasSuffix(" per request") == true)
    // Two facts that are sentences take the whole row.
    #expect(inspector.facts.filter(\.isWide).map(\.term) == ["Used", "Came from"])
    #expect(page.strip.selected?.count == segment.tokens.value)
    #expect(ContextPresenter.page(analysis, figures).inspector == nil)
  }

  @Test("a lane of one request and a lane of none still say something")
  func shortLanes() throws {
    let one = Self.analysis(.oneRequest)
    let page = ContextPresenter.page(one, one.figures(at: 0))
    #expect(page.cards[2].detail.hasPrefix("1 request · "))
    #expect(page.blocks.rows.allSatisfy { $0.carried == "1 req" })
    var judge = LexicalJudge()
    let empty = LaneAnalysis(
      session: "none", lane: Lane(id: .main, window: .given(200_000), segments: [], snapshots: []),
      references: judge.report())
    let nothing = ContextPresenter.page(empty, empty.figures(at: 0))
    #expect(nothing.cards[0].figure == "0")
    #expect(nothing.cards[2].detail == "0 requests · 0 prompts · 0 cache breaks")
    #expect(nothing.blocks.rows.isEmpty)
    #expect(nothing.legend.isEmpty)
    #expect(nothing.strip.slices.isEmpty)
  }

  @Test("the strip finds the block under the pointer by a search over the starts")
  func hitTesting() throws {
    let analysis = Self.analysis()
    let strip = ContextPresenter.page(analysis, analysis.figures(at: analysis.lastRequest)).strip
    for (index, slice) in strip.slices.enumerated() where slice.tokens > 0 {
      #expect(strip.slice(at: Double(slice.start)) == index)
      #expect(strip.slice(at: Double(slice.end) - 0.5) == index)
    }
    #expect(strip.slice(at: Double(try #require(strip.slices.last).end)) == nil)
    #expect(strip.slice(at: -1) == nil)
    #expect(strip.neighborhood(of: 0, count: 9) == 0..<9)
    #expect(
      strip.neighborhood(of: strip.slices.count - 1, count: 9).upperBound == strip.slices.count)
    #expect(MagnifierWords.window(3..<12, of: 1284) == "blocks 4–12 of 1,284")
  }

  /// The strip's magnifier is headed the way the timeline's is: the request
  /// at the playhead, counted from one, and its size and cost.
  @Test("the strip's magnifier names its request the way the timeline's does")
  func magnifierHeading() {
    let analysis = Self.analysis()
    let figures = analysis.figures(at: 10)
    let strip = ContextPresenter.page(analysis, figures).strip
    #expect(strip.request == "Request 11")
    #expect(
      strip.figures
        == MagnifierWords.figures(
          tokens: figures.column.end, dollars: figures.cost?.context ?? 0))
    let data = TimelinePresenter.present(
      lane: analysis.lane, costs: analysis.costs, cache: analysis.cache,
      prompts: analysis.prompts, order: analysis.readingOrder, promptLines: [:],
      selectedPrompt: nil)
    #expect(data.chart.columns[10].title == strip.request)
    #expect(data.chart.columns[10].figures == strip.figures)
  }
}
