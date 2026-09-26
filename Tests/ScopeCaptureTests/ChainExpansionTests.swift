import Foundation
import ScopeCore
import Testing

@testable import ScopeCapture

@Suite("Chain expansion")
struct ChainExpansionTests {
  /// One request issuing two calls, written the way Claude Code writes it:
  /// one entry per tool_use, and each result parented to its own call, so the
  /// parent chain runs through the second result only.
  static func parallelEntries() throws -> [TranscriptEntry] {
    func entry(_ json: String) throws -> TranscriptEntry {
      TranscriptEntry(try JSONValue(parsing: Data(json.utf8)))
    }
    return [
      try entry(
        """
        {"type":"assistant","uuid":"t1","parentUuid":"u0","requestId":"r1",
         "message":{"model":"m","content":[{"type":"tool_use","id":"c1","name":"Read",
         "input":{"file_path":"/a/one.swift"}}],"usage":{"input_tokens":1,
         "cache_read_input_tokens":99,"cache_creation_input_tokens":0,"output_tokens":20}}}
        """),
      try entry(
        """
        {"type":"assistant","uuid":"t2","parentUuid":"t1","requestId":"r1",
         "message":{"model":"m","content":[{"type":"tool_use","id":"c2","name":"Bash",
         "input":{"command":"ls"}}],"usage":{"input_tokens":1,
         "cache_read_input_tokens":99,"cache_creation_input_tokens":0,"output_tokens":20}}}
        """),
      try entry(
        """
        {"type":"user","uuid":"rA","parentUuid":"t1","message":{"content":
         [{"type":"tool_result","tool_use_id":"c1","content":"one"}]}}
        """),
      try entry(
        """
        {"type":"user","uuid":"rB","parentUuid":"t2","message":{"content":
         [{"type":"tool_result","tool_use_id":"c2","content":"two"}]}}
        """),
    ]
  }

  @Test("a sibling result is put back into the context")
  func siblingResultIsAttached() throws {
    let entries = try Self.parallelEntries()
    let expansion = ChainExpansion(entries: entries)
    // The parent walk reaches t1, t2 and rB. rA hangs off t1.
    let result = expansion.expand(added: ["t1", "t2", "rB"]) { _ in false }
    #expect(result.added.contains("rA"))
    #expect(result.added.count == 4)
    #expect(result.attached["t1"] == ["rA"])
    #expect(result.toolCalls == 2)
    #expect(result.toolCallsWithResult == 2)
  }

  @Test("results follow the calls that produced them")
  func order() throws {
    let expansion = ChainExpansion(entries: try Self.parallelEntries())
    let result = expansion.expand(added: ["t1", "t2", "rB"]) { _ in false }
    let calls = result.added.firstIndex(of: "t2") ?? 0
    let attached = result.added.firstIndex(of: "rA") ?? 0
    #expect(calls < attached)
  }

  @Test("a result already in the context is not added twice")
  func noDoubleAdd() throws {
    let expansion = ChainExpansion(entries: try Self.parallelEntries())
    let result = expansion.expand(added: ["t1", "t2", "rB"]) { $0 == "rA" }
    #expect(!result.added.contains("rA"))
    #expect(result.toolCalls == 2)
  }

  @Test("a call whose result never arrived is counted as such")
  func missingResult() throws {
    func entry(_ json: String) throws -> TranscriptEntry {
      TranscriptEntry(try JSONValue(parsing: Data(json.utf8)))
    }
    let entries = [
      try entry(
        """
        {"type":"assistant","uuid":"t1","parentUuid":"u0","requestId":"r1",
         "message":{"model":"m","content":[{"type":"tool_use","id":"c1","name":"Read",
         "input":{}}],"usage":{"input_tokens":1,"cache_read_input_tokens":9,
         "cache_creation_input_tokens":0,"output_tokens":5}}}
        """)
    ]
    let result = ChainExpansion(entries: entries).expand(added: ["t1"]) { _ in false }
    #expect(result.toolCalls == 1)
    #expect(result.toolCallsWithResult == 0)
  }

  @Test("every tool call of a real session with parallel calls has its result")
  func realSession() throws {
    let output = try AdapterTests.lane("parallel-calls")
    #expect(output.lane.stats.toolCalls > 20)
    #expect(output.lane.stats.toolCallsWithoutResult == 0)
    let validation = Validator.run(output.lane)
    #expect(
      validation.checks.first { $0.name == "tool calls brought their results" }?.passed
        == true)
    #expect(validation.mismatches.isEmpty)
  }
}
