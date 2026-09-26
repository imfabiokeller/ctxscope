/// The band list. This file is its only home: adapters map
/// harness content onto these cases, the UI reads them back, nobody redeclares
/// them.

/// A group of bands. Families are the hues of the UI.
public enum Family: String, Sendable, Codable, CaseIterable {
  case prefix
  case dialogue
  case reasoning
  case results
  /// Tokens the transcript cannot assign to any block. Its own family, and
  /// last, so the four families that mean something keep their hues and their
  /// places.
  case unattributed
}

/// Who put a segment into the context.
public enum Source: String, Sendable, Codable, CaseIterable {
  case harness
  case user
  case agent
  /// Nobody knows. Booking this under the harness made the harness column a
  /// quarter too large on a real session.
  case unknown
}

/// A category of segments, ordered by prompt position, which is also cache
/// stability: stable prefix first, volatile tail last.
public enum Band: String, Sendable, Codable, CaseIterable {
  case sys
  case tools
  case mcp
  case mem
  /// Tokens the measured totals say are in the context and no recorded block
  /// accounts for. It is not part of the prefix: booking it there inflated
  /// prefix overhead by a quarter in one real lane.
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

/// What a block is, in the six words the window uses: the legend, the kind
/// toggles, the stacked columns. Declared in reading order, the order the
/// model reads them in and the order every legend lists them in.
///
/// Unattributed tokens have no kind. Nothing recorded says what they are, so
/// they are drawn as an untyped remainder rather than booked under a kind
/// they might not be.
public enum Kind: String, Sendable, Codable, CaseIterable {
  case system
  case tools
  case memory
  case you
  case agent
  case results
}

public enum BandRegistry {
  /// Bands in prompt order. `Band.allCases` is declared in that order, and
  /// this is the accessor everything else uses.
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

  /// The kind a band is shown as. The one mapping from bands to kinds; nil
  /// for unattributed tokens, which have none.
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

  /// The bands shown as one kind, in prompt order.
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

  /// Whether reuse of a segment's content can be observed at all. Rules and
  /// schemas cannot: nothing in the output has to quote them to have followed
  /// them, and in transcript mode their text is never seen.
  public static func isAssessable(_ band: Band) -> Bool {
    switch band {
    case .sys, .mem, .tools, .mcp, .unattr: false
    default: true
    }
  }

  /// Whether a band's reuse belongs in the ratio of reused tokens.
  ///
  /// A tool definition is judged by whether its tool was called, which is a
  /// yes or a no rather than a share of words. Averaging that into a word
  /// overlap ratio moves the ratio without saying anything about words: on one
  /// real session it lifted the input side share from 4.0 to 6.3 percent, and
  /// on another it dropped the first request from 24 to 10. The blocks are
  /// still judged, still brighten in the chart when their tool is called, and
  /// still rank in the largest unused table when it never is.
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
