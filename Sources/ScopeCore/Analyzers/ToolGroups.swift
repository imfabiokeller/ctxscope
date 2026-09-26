/// Tool definitions grouped by the server that offers them: the built-in
/// tools, then one group per MCP server.
///
/// The server is read off the label the capture layer gave the block, which
/// is `ContextReport.Tool.label`: the harness's own tool name, which carries
/// the server as `mcp__<server>__<verb>`, or the name followed by the server in
/// parentheses when the name does not carry it.

/// Who offers a tool definition.
public enum ToolServer: Sendable, Codable, Hashable {
  case builtIn
  /// An MCP server, by the id the tool name carries. Nil when the block is an
  /// MCP share of the prefix that nothing named.
  case mcp(String?)
}

public struct ToolGroup: Sendable, Codable, Hashable {
  public let server: ToolServer
  /// The definitions, in reading order.
  public let segments: [SegmentID]
  public let tokens: Tokens
  /// The request the first of them entered at.
  public let born: Int
  /// Definitions whose tool had been called by the request asked about.
  public let called: Int
  /// Definitions a call can be observed for at all. A share of the prefix
  /// that nothing named is not one of them.
  public let named: Int

  public var definitions: Int { segments.count }
}

public enum ToolGroupAnalyzer {
  /// The server of a tool definition, or nil for a block that is not one.
  public static func server(of segment: Segment) -> ToolServer? {
    switch segment.band {
    case .tools: .builtIn
    case .mcp: .mcp(server(inLabel: segment.label))
    default: nil
    }
  }

  /// The server id a tool label carries, if it carries one.
  static func server(inLabel label: String) -> String? {
    let prefix = ContextReport.Tool.mcpPrefix
    if label.hasPrefix(prefix) {
      let rest = label.dropFirst(prefix.count)
      guard let end = rest.range(of: "__"), end.lowerBound > rest.startIndex else { return nil }
      return String(rest[rest.startIndex..<end.lowerBound])
    }
    guard label.hasSuffix(")"), let open = label.range(of: " (", options: .backwards) else {
      return nil
    }
    let server = label[open.upperBound..<label.index(before: label.endIndex)]
    return server.isEmpty ? nil : String(server)
  }

  /// The groups live at a request: built-in first, then each MCP server in
  /// the order it arrived.
  public static func run(
    _ lane: Lane, findings: [SegmentID: ReferenceFinding], at request: Int
  ) -> [ToolGroup] {
    var order: [ToolServer] = []
    var members: [ToolServer: [Segment]] = [:]
    for segment in lane.promptOrderSegments(at: request) {
      guard let server = server(of: segment) else { continue }
      if members[server] == nil { order.append(server) }
      members[server, default: []].append(segment)
    }
    // Reading order already puts the built-in band before the MCP band and
    // sorts each by the request a block entered at, so the order of first
    // appearance is the order the groups are listed in.
    return order.map { server -> ToolGroup in
      let segments = members[server] ?? []
      var called = 0
      var named = 0
      for segment in segments {
        guard
          let calledYet = UseAnalyzer.called(
            segment, finding: findings[segment.id], at: request)
        else { continue }
        named += 1
        if calledYet { called += 1 }
      }
      return ToolGroup(
        server: server,
        segments: segments.map(\.id),
        tokens: segments.reduce(Tokens(0, .measured)) { $0 + $1.tokens },
        born: segments.map(\.born).min() ?? request,
        called: called,
        named: named
      )
    }
  }
}
