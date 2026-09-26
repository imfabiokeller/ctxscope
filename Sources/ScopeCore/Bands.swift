public enum Family: String, Sendable, Codable, CaseIterable {
  case prefix
  case dialogue
  case reasoning
  case results
  /// Last, so the other families keep their hues and places.
  case unattributed
}

public enum Source: String, Sendable, Codable, CaseIterable {
  case harness
  case user
  case agent
  case unknown
}

/// Declared in prompt order: `BandRegistry.ordered` relies on it.
public enum Band: String, Sendable, Codable, CaseIterable {
  case sys
  case tools
  case mcp
  case mem
  case unattr
  case user
  case asst
  case think
  case call
  case read
  case bash
  case srch
  case agent
}

/// Declared in reading order, which is the order every legend lists them in.
public enum Kind: String, Sendable, Codable, CaseIterable {
  case system
  case tools
  case memory
  case you
  case agent
  case results
}

public enum BandRegistry {
  public static let ordered: [Band] = Band.allCases

  public static func family(of band: Band) -> Family {
    switch band {
    case .sys, .tools, .mcp, .mem: .prefix
    case .unattr: .unattributed
    case .user, .asst: .dialogue
    case .think, .call: .reasoning
    case .read, .bash, .srch, .agent: .results
    }
  }

  public static func kind(of band: Band) -> Kind? {
    switch band {
    case .sys: .system
    case .tools, .mcp: .tools
    case .mem: .memory
    case .unattr: nil
    case .user: .you
    case .asst, .think, .call: .agent
    case .read, .bash, .srch, .agent: .results
    }
  }

  public static func bands(of wanted: Kind) -> [Band] {
    ordered.filter { kind(of: $0) == wanted }
  }

  public static func source(of band: Band) -> Source {
    switch band {
    case .sys, .tools: .harness
    case .unattr: .unknown
    case .mcp, .mem, .user: .user
    case .asst, .think, .call, .read, .bash, .srch, .agent: .agent
    }
  }

  public static func label(of band: Band) -> String {
    switch band {
    case .sys: "System prompt"
    case .tools: "Tool schemas"
    case .mcp: "MCP schemas"
    case .mem: "Memory files"
    case .unattr: "Unattributed"
    case .user: "User"
    case .asst: "Assistant"
    case .think: "Thinking"
    case .call: "Tool calls"
    case .read: "File reads"
    case .bash: "Shell output"
    case .srch: "Search results"
    case .agent: "Subagent returns"
    }
  }

  public static func isAssessable(_ band: Band) -> Bool {
    switch band {
    case .sys, .mem, .tools, .mcp, .unattr: false
    default: true
    }
  }

  /// Tool definitions are judged by whether their tool was called, a yes or no,
  /// not a share of words, so they stay out of this ratio.
  public static func countsTowardsReuseRatio(_ band: Band) -> Bool {
    band != .tools && band != .mcp
  }

  public static func bands(in wanted: Family) -> [Band] {
    ordered.filter { family(of: $0) == wanted }
  }

  public static func position(of band: Band) -> Int {
    ordered.firstIndex(of: band) ?? 0
  }
}
