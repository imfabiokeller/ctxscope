public enum ToolServer: Sendable, Codable, Hashable {
  case builtIn
  case mcp(String?)
}

public struct ToolGroup: Sendable, Codable, Hashable {
  public let server: ToolServer
  public let segments: [SegmentID]
  public let tokens: Tokens
  public let born: Int
  public let called: Int
  public let named: Int

  public var definitions: Int { segments.count }
}

public enum ToolGroupAnalyzer {
  public static func server(of segment: Segment) -> ToolServer? {
    switch segment.band {
    case .tools: .builtIn
    case .mcp: .mcp(server(inLabel: segment.label))
    default: nil
    }
  }

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
    // Reading order puts built-in before MCP, so first appearance is the listing order.
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
