/// Deferred categories are not in the context and are left out
/// (docs/TRANSCRIPT_FORMAT.md section 12).
public struct ContextReport: Sendable, Hashable, Codable {
  public struct Tool: Sendable, Hashable, Codable {
    public let name: String
    public let server: String?
    public let tokens: Int?
    public let characters: Int
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

    /// The `server` key only arrived in Claude Code 2.1.266, so the
    /// `mcp__<server>__<verb>` name is checked too.
    public static let mcpPrefix = "mcp__"

    public var isMCP: Bool { server != nil || name.hasPrefix(Self.mcpPrefix) }

    /// The name carries the server id with punctuation replaced by underscores.
    public var label: String {
      guard let server, !server.isEmpty,
        !Self.flattened(name).contains(Self.flattened(server))
      else { return name }
      return "\(name) (\(server))"
    }

    static func flattened(_ text: String) -> String {
      String(text.map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }
  }

  public var request: Int
  public let systemPrompt: Int
  public let systemTools: Int
  public let mcpTools: Int
  public let memoryFiles: Int
  public let skills: Int
  public let messages: Int
  public let total: Int
  /// Loaded and deferred alike, with nothing saying which: evidence about sizes only.
  public let reportedTools: [Tool]
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

  /// Messages and skills are not prefix: the transcript records both as content of their own.
  public var prefixTokens: Int { systemPrompt + systemTools + mcpTools + memoryFiles }

  public var isUsable: Bool { prefixTokens > 0 }
}

extension PrefixSplit {
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
