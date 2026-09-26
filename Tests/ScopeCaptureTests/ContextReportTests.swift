import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture

/// The numbers are invented; the shape is `docs/TRANSCRIPT_FORMAT.md` section 12.
@Suite("the context report")
struct ContextReportTests {
  static func entry(
    used: [(String, Int)] = [
      ("System prompt", 5000), ("System tools", 15000), ("MCP tools", 15000),
      ("Memory files", 1600), ("Skills", 9600), ("Messages", 493_000),
    ],
    deferred: [(String, Int)] = [
      ("MCP tools (deferred)", 118_000), ("System tools (deferred)", 20_000),
    ],
    mcpRows: [(String, Int)] = [],
    kinds: Bool = true
  ) -> [String: Any] {
    var categories: [[String: Any]] = used.map { name, tokens in
      var row: [String: Any] = ["name": name, "tokens": tokens]
      if kinds { row["kind"] = "used" }
      return row
    }
    categories += deferred.map { name, tokens in
      var row: [String: Any] = ["name": name, "tokens": tokens]
      if kinds { row["kind"] = "deferred" }
      return row
    }
    var free: [String: Any] = ["name": "Free space", "tokens": 426_000]
    if kinds { free["kind"] = "free" }
    categories.append(free)
    return [
      "type": "system",
      "subtype": "local_command",
      "uuid": UUID().uuidString,
      "contextUsage": [
        "model": "test-model",
        "total_tokens": 539_200,
        "raw_max_tokens": 1_000_000,
        "categories": categories,
        "mcp_tools": mcpRows.map { ["name": $0.0, "server_name": "srv-1", "tokens": $0.1] },
        "memory_files": [],
        "skills": [],
        "agents": [],
      ],
    ]
  }

  static func read(_ object: [String: Any]) throws -> ContextReport? {
    let data = try JSONSerialization.data(withJSONObject: object)
    return ContextUsage.report(of: TranscriptEntry(try JSONValue(parsing: data)))
  }

  @Test("only the categories that are in the context are read")
  func onlyUsedCategories() throws {
    let report = try #require(try Self.read(Self.entry()))
    #expect(report.systemPrompt == 5000)
    #expect(report.systemTools == 15_000)
    #expect(report.mcpTools == 15_000)
    #expect(report.memoryFiles == 1600)
    #expect(report.skills == 9600)
    #expect(report.messages == 493_000)
    #expect(report.prefixTokens == 36_600)
  }

  @Test("a category with no kind is read by its name")
  func noKindField() throws {
    let report = try #require(try Self.read(Self.entry(kinds: false)))
    #expect(report.systemTools == 15_000)
    #expect(report.prefixTokens == 36_600)
  }

  @Test("a report whose categories are not recognized is not a report")
  func malformedReport() throws {
    let scrambled = Self.entry(
      used: [("bravo charlie", 5000), ("delta echo", 15_000)], deferred: [])
    #expect(try Self.read(scrambled) == nil)
    var missing = Self.entry()
    missing["contextUsage"] = ["total_tokens": 1]
    #expect(try Self.read(missing) == nil)
    var wrongKind = Self.entry()
    wrongKind["subtype"] = "stop_hook_summary"
    #expect(try Self.read(wrongKind) == nil)
  }

  @Test("only the tools of the request take the report's sizes")
  func joinedWithTheSnapshot() throws {
    let report = try #require(
      try Self.read(
        Self.entry(mcpRows: [("mcp__a__one", 9000), ("mcp__a__two", 6000), ("deferred", 118_000)])
      ))
    let request = [
      ContextReport.Tool(name: "Read", server: nil, tokens: nil, characters: 400),
      ContextReport.Tool(name: "mcp__a__one", server: "srv-1", tokens: nil, characters: 0),
      ContextReport.Tool(name: "mcp__a__two", server: "srv-1", tokens: nil, characters: 0),
    ]
    let joined = ContextUsage.joined(report, tools: request)
    #expect(joined.tools.count == 3)
    #expect(joined.tools.filter(\.isMCP).compactMap(\.tokens).reduce(0, +) == 15_000)
    #expect(!joined.tools.contains { $0.name == "deferred" })
  }

  @Test("the parts follow the report, one per tool where the tools are known")
  func partsFromReport() throws {
    let report = try #require(
      try Self.read(Self.entry(mcpRows: [("mcp__a__one", 9000), ("mcp__a__two", 6000)])))
    let joined = ContextUsage.joined(
      report,
      tools: [
        ContextReport.Tool(name: "Read", server: nil, tokens: nil, characters: 300),
        ContextReport.Tool(name: "Bash", server: nil, tokens: nil, characters: 100),
        ContextReport.Tool(name: "mcp__a__one", server: "srv-1", tokens: nil, characters: 0),
        ContextReport.Tool(name: "mcp__a__two", server: "srv-1", tokens: nil, characters: 0),
      ])
    let parts = PrefixSplit.plan(from: joined, observed: [.sys]).parts
    #expect(!parts.contains { $0.band == .sys })
    #expect(parts.filter { $0.band == .tools }.map(\.label) == ["Read", "Bash"])
    #expect(
      parts.filter { $0.band == .mcp }.map(\.label)
        == ["mcp__a__one (srv-1)", "mcp__a__two (srv-1)"])
    let tools = parts.filter { $0.band == .tools }.compactMap(\.reportedTokens)
    #expect(tools[0] == 3 * tools[1])
    let mcp = parts.filter { $0.band == .mcp }.compactMap(\.reportedTokens)
    #expect(mcp[0] == 9000)
    #expect(mcp[1] == 6000)
  }

  @Test("with no tools named, a band stays one block")
  func noToolsNamed() throws {
    let report = try #require(try Self.read(Self.entry()))
    let plan = PrefixSplit.plan(from: report)
    #expect(plan.parts.map(\.band) == [.sys, .tools, .mcp, .mem])
    #expect(plan.parts.allSatisfy { !$0.isShare })
    #expect(plan.parts.compactMap(\.reportedTokens).reduce(0, +) == report.prefixTokens)
  }

  /// The report is appended at the end, as in real sessions: it must be found before the file
  /// is read.
  static func laneWithReport(_ report: [String: Any]) throws -> Lane {
    let (url, _) = try IncrementalTests.split("short-session", at: 1.0)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let line = try JSONSerialization.data(withJSONObject: report)
    try IncrementalTests.append([String(decoding: line, as: UTF8.self)], to: url)
    var capture = SessionCapture(
      session: IncrementalTests.reference(url), includeSubagents: false, window: nil)
    try capture.refresh()
    return capture.finish().recording.lanes[0]
  }

  static func fixtureTools() throws -> [ContextReport.Tool] {
    var evidence = PrefixEvidence()
    for entry in try AdapterTests.fixture("short-session") { evidence.learn(from: entry) }
    return evidence.tools
  }

  @Test("a report at the end of a file still splits the prefix at the first request")
  func reportAppliesToTheWholeLane() throws {
    let tools = try Self.fixtureTools().filter(\.isMCP)
    #expect(tools.count > 2)
    let rows = tools.enumerated().map { ($0.element.name, 100 * ($0.offset + 1)) }
    let lane = try Self.laneWithReport(Self.entry(mcpRows: rows))

    #expect(lane.prefixSource == .snapshotAndReport)
    let mcp = lane.segments.filter { $0.band == .mcp }
    #expect(mcp.count == tools.count)
    #expect(mcp.map(\.label) == tools.map(\.label))
    let first = try #require(mcp.first?.tokens.value)
    let last = try #require(mcp.last?.tokens.value)
    #expect(last > first)
    #expect(lane.segments.contains { $0.band == .unattr && $0.born == 0 })
    // The invented report fits a session ten times this size, so only the totals check matters.
    let checks = Validator.run(lane)
    #expect(checks.mismatches.isEmpty)
    #expect(checks.checks.first { $0.name == "totals equal API usage" }?.passed == true)
  }

  @Test("a report that does not parse leaves the prefix as it was")
  func malformedReportFallsBack() throws {
    // Renamed categories, as a changed harness version would write them.
    let lane = try Self.laneWithReport(
      Self.entry(used: [("bravo charlie", 5000), ("delta echo", 15_000)], deferred: []))
    #expect(lane.prefixSource == .snapshot)
    let tools = try Self.fixtureTools()
    #expect(
      lane.segments.count { $0.band == .mcp && $0.born == 0 } == tools.count(where: \.isMCP))
    #expect(!lane.segments.contains { $0.band == .unattr && $0.born == 0 })
    #expect(Validator.run(lane).passed)
  }

  @Test("a lane with neither record falls back to the prior alone")
  func priorOnly() throws {
    let lane = try AdapterTests.lane("compaction-session").lane
    #expect(lane.prefixSource == .prior)
    #expect(lane.segments.filter { $0.band == .mcp && $0.born == 0 }.count == 1)
    #expect(lane.segments.filter { $0.band == .tools && $0.born == 0 }.count == 1)
  }
}
