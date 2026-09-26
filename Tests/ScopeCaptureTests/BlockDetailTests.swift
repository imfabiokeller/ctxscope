import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture

@Suite("block details")
struct BlockDetailTests {
  static func input(_ object: [String: Any]) -> JSONValue { JSONValue(any: object) }

  @Test("a command is told by its description, else by its first line")
  func bash() {
    let described = BlockDetail.tool(
      "Bash", input: Self.input(["command": "npm test -- --all", "description": "Run the tests"]),
      project: nil)
    #expect(described == BlockDetail(head: "Bash", detail: "Run the tests"))
    let plain = BlockDetail.tool(
      "Bash", input: Self.input(["command": "\ngit diff\n  --stat"]), project: nil)
    #expect(plain?.detail == "git diff")
    let call = BlockDetail.tool(
      "Bash", input: Self.input(["command": "git diff"]), project: nil, isCall: true)
    #expect(call == BlockDetail(head: "Bash call", detail: "git diff"))
  }

  @Test("a file is told by its path in the project, cut in the middle")
  func paths() throws {
    let read = BlockDetail.tool(
      "Read", input: Self.input(["file_path": "/code/api/src/api/client.ts"]),
      project: "/code/api")
    #expect(read == BlockDetail(head: "Read", detail: "src/api/client.ts"))
    let outside = BlockDetail.tool(
      "Edit", input: Self.input(["file_path": "/etc/hosts"]), project: "/code/api")
    #expect(outside?.detail == "/etc/hosts")
    #expect(
      BlockDetail.path("/Users/me/.claude/memory/MEMORY.md", project: "/code", home: "/Users/me")
        == "~/.claude/memory/MEMORY.md")
    let deep = "/code/api/" + Array(repeating: "folder", count: 20).joined(separator: "/")
    let long = try #require(
      BlockDetail.tool(
        "Write", input: Self.input(["file_path": deep + "/retry_policy.ts"]), project: "/code/api"))
    #expect(long.detail.count == BlockDetail.limit)
    #expect(long.detail.hasPrefix("folder/"))
    #expect(long.detail.hasSuffix("/retry_policy.ts"))
    #expect(long.detail.contains("\u{2026}"))
  }

  @Test("a search is told by its pattern and, once it returned, its count")
  func search() {
    let grep = BlockDetail.tool(
      "Grep", input: Self.input(["pattern": "backoff"]),
      result: Self.input(["mode": "content", "numLines": 212]), project: nil)
    #expect(grep?.detail == "\"backoff\" (212 matches)")
    let files = BlockDetail.tool(
      "Grep", input: Self.input(["pattern": "backoff"]),
      result: Self.input(["mode": "files_with_matches", "numFiles": 1]), project: nil)
    #expect(files?.detail == "\"backoff\" (1 file)")
    let call = BlockDetail.tool("Glob", input: Self.input(["pattern": "**/*.ts"]), project: nil)
    #expect(call?.detail == "\"**/*.ts\"")
  }

  @Test("the web, a subagent and an MCP tool")
  func others() {
    let fetch = BlockDetail.tool(
      "WebFetch",
      input: Self.input(["url": "https://www.developer.mozilla.org/en-US/docs/Math?x=1"]),
      project: nil)
    #expect(fetch?.detail == "developer.mozilla.org/en-US/docs/Math")
    let search = BlockDetail.tool(
      "WebSearch", input: Self.input(["query": "jitter cap"]), project: nil)
    #expect(search?.detail == "\"jitter cap\"")
    let agent = BlockDetail.tool(
      "Agent", input: Self.input(["description": "Find the callers", "prompt": "long"]),
      project: nil)
    #expect(agent == BlockDetail(head: "Agent", detail: "Find the callers"))
    let mcp = BlockDetail.tool("mcp__github__create_issue", input: nil, project: nil)
    #expect(mcp == BlockDetail(head: "github", detail: "create_issue"))
    let skill = BlockDetail.tool("Skill", input: Self.input(["skill": "review"]), project: nil)
    #expect(skill?.detail == "review")
    #expect(BlockDetail.tool("TaskList", input: Self.input([:]), project: nil) == nil)
  }

  @Test("written text by its first line, an attachment by its file or its type")
  func lines() {
    #expect(
      BlockDetail.line("Thinking", text: "\n plan the   cap\nmore")
        == BlockDetail(head: "Thinking", detail: "plan the cap"))
    #expect(BlockDetail.line("Thinking", text: " \n") == nil)
    #expect(
      BlockDetail.attachment(type: "skill_listing", record: nil, project: nil).detail
        == "skill listing")
    #expect(
      BlockDetail.attachment(
        type: "edited_text_file", record: Self.input(["filename": "/code/api/a.ts"]),
        project: "/code/api"
      ).detail == "a.ts")
  }

  @Test("a lane's calls and results are told by the call's input, read back from the file")
  func fromTheTranscript() throws {
    let url = try #require(
      Bundle.module.url(forResource: "Fixtures/short-session", withExtension: "jsonl"))
    var builder = LaneBuilder(
      id: .main, agentType: nil, parentToolUseID: nil, window: nil, url: url)
    builder.append(try ClaudeCodeAdapter.entries(at: url))
    let lane = builder.finish().lane
    let details = builder.details(of: lane.segments.map(\.id))
    let reads = lane.segments.filter { $0.band == .read && $0.label.hasPrefix("Read") }
    #expect(!reads.isEmpty)
    for segment in reads {
      let detail = try #require(details[segment.id])
      #expect(detail.head == "Read")
      // The fixture's files are outside its project, so the path stays whole.
      #expect(detail.detail.hasPrefix("/") || detail.detail.contains("\u{2026}"))
    }
    let searches = lane.segments.filter { $0.label == "WebSearch result" }
    #expect(!searches.isEmpty)
    #expect(searches.allSatisfy { details[$0.id]?.head == "WebSearch" })
    let prefix = lane.segments.filter { $0.band == .sys || $0.band == .tools }
    #expect(prefix.allSatisfy { details[$0.id] == nil })
    #expect(details.values.allSatisfy { $0.detail.count <= BlockDetail.limit })
  }
}
