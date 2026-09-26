import Testing

@testable import ScopeCore

/// What a tool record says about itself, which decides its band and its name
/// on screen.
@Suite("a tool record")
struct PrefixToolTests {
  static func tool(_ name: String, server: String? = nil) -> ContextReport.Tool {
    ContextReport.Tool(name: name, server: server, tokens: nil, characters: 10)
  }

  /// Claude Code 2.1.260 writes no `server` key at all, so five sessions on
  /// this machine put 27 MCP tools into TOOLS beside an MCP block the prior
  /// had invented.
  @Test("an MCP tool is one the server names or the name does")
  func mcpByEitherHalf() {
    #expect(Self.tool("mcp__abc__verb").isMCP)
    #expect(Self.tool("Read", server: "abc").isMCP)
    #expect(!Self.tool("Read").isMCP)
    #expect(!Self.tool("NotebookEdit").isMCP)
  }

  /// The name carries the server id with its punctuation flattened, so a
  /// label that compares them literally says the server twice.
  @Test("the server is named once")
  func serverNamedOnce() {
    let dashed = Self.tool(
      "mcp__1a59c906_04da_521d__batch", server: "1a59c906-04da-521d")
    #expect(dashed.label == "mcp__1a59c906_04da_521d__batch")
    #expect(Self.tool("mcp__abc__verb", server: "abc").label == "mcp__abc__verb")
    // A server the name really does not carry is still worth saying.
    #expect(Self.tool("browse", server: "srv-1").label == "browse (srv-1)")
    #expect(Self.tool("Read").label == "Read")
  }
}
