internal import Foundation
internal import ScopeCore

/// Reads the harness's own `/context` report out of a transcript.
///
/// Claude Code writes the run as a `system` entry with
/// `subtype: "local_command"`, a markdown `content` for the transcript view
/// and a structured `contextUsage` object beside it. The object is what is
/// read here: the markdown is the same numbers rounded to a tenth of a
/// thousand.
///
/// Everything about it is optional. A version that writes a shape this does
/// not know returns nothing and the lane falls back to what it had, which is
/// why every lookup below is a question rather than an assumption.
enum ContextUsage {
  /// Categories that are in the context. The harness also lists deferred tool
  /// schemas, an autocompact buffer and free space, which are not.
  static let usedKind = "used"

  /// Category names, as the harness writes them. Matched case insensitively
  /// and only against categories it marked as being in the context, so a
  /// renamed deferred category can never be taken for a used one.
  enum Category: String, CaseIterable {
    case systemPrompt = "system prompt"
    case systemTools = "system tools"
    case mcpTools = "mcp tools"
    case memoryFiles = "memory files"
    case skills = "skills"
    case messages = "messages"
  }

  /// Whether an entry is a `/context` run at all, which is cheaper to ask than
  /// whether it parses into a report.
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
      // With no `kind` written at all, a category is taken at its name: the
      // deferred ones say so in theirs.
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

  /// The per tool rows of the report. They cover the tools that are loaded and
  /// the ones that are only deferred, and nothing in a row says which, so the
  /// prompt snapshot's own tool list is what picks the loaded ones out later.
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

  /// The report as it applies to this lane: the categories the harness
  /// reported, with the tools of the request named.
  ///
  /// The report's own MCP rows are dropped for any tool the snapshot does not
  /// name, because those are the deferred ones. On the session this was read
  /// from, the 30 rows the snapshot names sum to 14896 tokens, which is the
  /// MCP category exactly, while all 242 rows sum to 133378, which is that
  /// plus the deferred category exactly.
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
