import Testing

@testable import ScopeCore

@Suite("a tool record")
struct PrefixToolTests {
  static func tool(_ name: String, server: String? = nil) -> ContextReport.Tool {
    ContextReport.Tool(name: name, server: server, tokens: nil, characters: 10)
  }

  /// Claude Code 2.1.260 writes no `server` key.
  @Test("an MCP tool is one the server names or the name does")
  func mcpByEitherHalf() {
    #expect(Self.tool("mcp__abc__verb").isMCP)
    #expect(Self.tool("Read", server: "abc").isMCP)
    #expect(!Self.tool("Read").isMCP)
    #expect(!Self.tool("NotebookEdit").isMCP)
  }

  /// The name carries the server id with its punctuation flattened.
  @Test("the server is named once")
  func serverNamedOnce() {
    let dashed = Self.tool(
      "mcp__1a59c906_04da_521d__batch", server: "1a59c906-04da-521d")
    #expect(dashed.label == "mcp__1a59c906_04da_521d__batch")
    #expect(Self.tool("mcp__abc__verb", server: "abc").label == "mcp__abc__verb")
    #expect(Self.tool("browse", server: "srv-1").label == "browse (srv-1)")
    #expect(Self.tool("Read").label == "Read")
  }
}
