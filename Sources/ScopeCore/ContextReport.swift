/// What the harness itself says fills the context, as its `/context` command
/// reports it.
///
/// It is not an API number, so it is not measured. It is the harness counting
/// its own prompt with its own tokenizer, which is a great deal better than a
/// fixed prior: on the session it was read from, the categories that are in
/// the context sum to `total` exactly, and the MCP rows the prompt snapshot
/// also names sum to the MCP category exactly.
///
/// The categories the harness calls deferred are not in the context. They are
/// the schemas of tools that would be loaded on demand, and they are left out
/// here for that reason. See `docs/TRANSCRIPT_FORMAT.md` section 12.
public struct ContextReport: Sendable, Hashable, Codable {
  /// One tool of the request, named by the prompt snapshot and, for an MCP
  /// tool, sized by the report.
  public struct Tool: Sendable, Hashable, Codable {
    public let name: String
    /// The MCP server that offers it. Nil for a built-in tool.
    public let server: String?
    /// What the harness reported this tool costs, when it reported it.
    public let tokens: Int?
    /// Length of its recorded definition, when a prompt snapshot recorded one.
    public let characters: Int
    /// Where it sits in the snapshot's tool list, so its definition can be
    /// read back out of the transcript by position.
    public let index: Int

    public init(
      name: String, server: String?, tokens: Int?, characters: Int, index: Int = 0
    ) {
      self.name = name
      self.server = server
      self.tokens = tokens
      self.characters = characters
      self.index = index
    }

    /// The `server` key only arrived in Claude Code 2.1.266. Before that a
    /// snapshot lists MCP tools with no mark at all, and reading only `server`
    /// put 27 of them into TOOLS beside an unreadable MCP block the prior had
    /// invented. The name is the other half of the answer and it is in every
    /// version: the harness writes an MCP tool as `mcp__<server>__<verb>`.
    public static let mcpPrefix = "mcp__"

    public var isMCP: Bool { server != nil || name.hasPrefix(Self.mcpPrefix) }

    /// Short and neutral: the tool's own name, and the server that offers it
    /// when the name does not already carry it.
    ///
    /// The name carries the server id with its punctuation replaced by
    /// underscores, so the two are compared with the same replacement made.
    /// Without it 20 of 30 labels on one real session said the server twice
    /// and ran to 67 characters.
    public var label: String {
      guard let server, !server.isEmpty,
        !Self.flattened(name).contains(Self.flattened(server))
      else { return name }
      return "\(name) (\(server))"
    }

    /// A name and a server id compare equal when only punctuation differs.
    static func flattened(_ text: String) -> String {
      String(text.map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }
  }

  /// The request the report was run at.
  public var request: Int
  public let systemPrompt: Int
  public let systemTools: Int
  public let mcpTools: Int
  public let memoryFiles: Int
  public let skills: Int
  public let messages: Int
  /// What the harness said is in the context in total, which is the sum of the
  /// categories above.
  public let total: Int
  /// Every MCP tool the report listed, loaded and deferred alike. Nothing in a
  /// row says which it is, so this is evidence about sizes and not a list of
  /// what is in the context.
  public let reportedTools: [Tool]
  /// The tools of the request, as a prompt snapshot named them, carrying the
  /// sizes the report gave the MCP ones. Empty when no snapshot named them, in
  /// which case TOOLS and MCP stay one block each.
  public var tools: [Tool]

  public init(
    request: Int = 0,
    systemPrompt: Int,
    systemTools: Int,
    mcpTools: Int,
    memoryFiles: Int,
    skills: Int,
    messages: Int,
    total: Int,
    reportedTools: [Tool] = [],
    tools: [Tool] = []
  ) {
    self.request = request
    self.systemPrompt = systemPrompt
    self.systemTools = systemTools
    self.mcpTools = mcpTools
    self.memoryFiles = memoryFiles
    self.skills = skills
    self.messages = messages
    self.total = total
    self.reportedTools = reportedTools
    self.tools = tools
  }

  /// The categories that belong to the prefix. Messages and skills do not:
  /// the transcript records both as content of their own.
  public var prefixTokens: Int { systemPrompt + systemTools + mcpTools + memoryFiles }

  /// A report with nothing in its prefix says nothing about the prefix.
  public var isUsable: Bool { prefixTokens > 0 }
}

extension PrefixSplit {
  /// The plan the harness's own report gives.
  ///
  /// Every category it counted is a size rather than a share, and inside a
  /// category the blocks the snapshot recorded share that size: the system
  /// prompt blocks by their lengths, the MCP tools by what the report said
  /// each costs, the built-in tools by the length of their schemas, because
  /// the report gives no per tool number for those.
  ///
  /// A band the transcript already put in the context as content of its own is
  /// left out, the same rule the prior follows.
  public static func plan(
    from report: ContextReport,
    systemLengths: [Int] = [],
    observed: Set<Band> = []
  ) -> Plan {
    var parts: [Part] = []
    if !observed.contains(.sys), report.systemPrompt > 0 {
      parts +=
        systemLengths.isEmpty
        ? [
          Part(
            band: .sys, label: BandRegistry.label(of: .sys),
            reportedTokens: report.systemPrompt)
        ]
        : systemParts(lengths: systemLengths, total: report.systemPrompt)
    }
    parts += bandParts(
      band: .tools, total: report.systemTools,
      tools: report.tools.filter { !$0.isMCP }, weight: { Double($0.characters) })
    parts += bandParts(
      band: .mcp, total: report.mcpTools,
      tools: report.tools.filter(\.isMCP),
      weight: { Double($0.tokens ?? $0.characters) })
    if !observed.contains(.mem), report.memoryFiles > 0 {
      parts.append(
        Part(
          band: .mem, label: BandRegistry.label(of: .mem),
          reportedTokens: report.memoryFiles))
    }
    return Plan(parts: parts)
  }

  /// A reported category total, divided among the tools the snapshot named.
  /// With no tools named the band stays one block of that size.
  private static func bandParts(
    band: Band,
    total: Int,
    tools: [ContextReport.Tool],
    weight: (ContextReport.Tool) -> Double
  ) -> [Part] {
    guard total > 0 else { return [] }
    let weights = tools.map { max(0, weight($0)) }
    guard !tools.isEmpty, weights.reduce(0, +) > 0 else {
      return [Part(band: band, label: BandRegistry.label(of: band), reportedTokens: total)]
    }
    let shares = Normalizer.allocate(total: total, weights: weights)
    return zip(tools, shares).map { toolPart($0, reported: $1) }
  }
}
