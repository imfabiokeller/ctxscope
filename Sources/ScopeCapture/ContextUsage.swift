internal import Foundation
internal import ScopeCore

// Claude Code writes `/context` as a `system` `local_command` entry; its
// `contextUsage` object is exact, the markdown beside it is rounded.
enum ContextUsage {
  // The harness also lists deferred tools, the autocompact buffer and free space.
  static let usedKind = "used"

  enum Category: String, CaseIterable {
    case systemPrompt = "system prompt"
    case systemTools = "system tools"
    case mcpTools = "mcp tools"
    case memoryFiles = "memory files"
    case skills = "skills"
    case messages = "messages"
  }

  static func isReport(_ entry: TranscriptEntry) -> Bool {
    entry.kind == "system" && entry.systemSubtype == "local_command"
      && entry.raw["contextUsage"] != nil
  }

  static func report(of entry: TranscriptEntry) -> ContextReport? {
    guard entry.kind == "system", entry.systemSubtype == "local_command",
      let usage = entry.raw["contextUsage"], let rows = usage["categories"]?.array
    else { return nil }

    var tokens: [Category: Int] = [:]
    let marked = rows.contains { $0["kind"]?.string != nil }
    for row in rows {
      // With no `kind` written at all, deferred categories are known by their names.
      let kind = row["kind"]?.string
      guard marked ? kind == usedKind : !Self.namesDeferred(row) else { continue }
      guard let name = row["name"]?.string?.lowercased(),
        let category = Category(rawValue: name), let value = row["tokens"]?.int
      else { continue }
      tokens[category, default: 0] += value
    }

    let report = ContextReport(
      systemPrompt: tokens[.systemPrompt] ?? 0,
      systemTools: tokens[.systemTools] ?? 0,
      mcpTools: tokens[.mcpTools] ?? 0,
      memoryFiles: tokens[.memoryFiles] ?? 0,
      skills: tokens[.skills] ?? 0,
      messages: tokens[.messages] ?? 0,
      total: usage["total_tokens"]?.int ?? 0,
      reportedTools: mcpTools(usage)
    )
    return report.isUsable ? report : nil
  }

  private static func namesDeferred(_ row: JSONValue) -> Bool {
    let name = row["name"]?.string?.lowercased() ?? ""
    return name.contains("deferred") || name.contains("free") || name.contains("buffer")
  }

  // Rows cover loaded and deferred tools alike and do not say which; the
  // snapshot's tool list picks the loaded ones.
  private static func mcpTools(_ usage: JSONValue) -> [ContextReport.Tool] {
    (usage["mcp_tools"]?.array ?? []).compactMap { row in
      guard let name = row["name"]?.string, let tokens = row["tokens"]?.int else { return nil }
      return ContextReport.Tool(
        name: name,
        server: row["server_name"]?.string ?? "",
        tokens: tokens,
        characters: 0
      )
    }
  }

  static func joined(_ report: ContextReport, tools: [ContextReport.Tool]) -> ContextReport {
    guard !tools.isEmpty else { return report }
    let reported = Dictionary(
      report.reportedTools.map { ($0.name, $0.tokens ?? 0) },
      uniquingKeysWith: { first, _ in first })
    var joined = report
    joined.tools = tools.map { tool in
      ContextReport.Tool(
        name: tool.name,
        server: tool.server,
        tokens: reported[tool.name],
        characters: tool.characters,
        index: tool.index
      )
    }
    return joined
  }
}
