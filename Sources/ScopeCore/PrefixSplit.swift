public enum PrefixSplit {
  /// The shape of a Claude Code prompt with a handful of MCP servers connected.
  public static let ratios: [(band: Band, share: Double)] = [
    (.sys, 0.18),
    (.tools, 0.42),
    (.mcp, 0.30),
    (.mem, 0.10),
  ]

  public enum Source: String, Sendable, Codable, CaseIterable {
    case prior
    case snapshot
    case report
    case snapshotAndReport = "snapshot+report"

    public static func of(snapshot: Bool, report: Bool) -> Source {
      switch (snapshot, report) {
      case (true, true): .snapshotAndReport
      case (true, false): .snapshot
      case (false, true): .report
      case (false, false): .prior
      }
    }
  }

  public struct Part: Sendable, Hashable {
    public enum Item: Sendable, Hashable {
      case systemBlock(Int)
      case tool(ContextReport.Tool)
    }

    public let band: Band
    public let label: String
    public let weight: Double
    public let characters: Int
    public let contentClass: ContentClass
    public let reportedTokens: Int?
    public let item: Item?

    public init(
      band: Band,
      label: String,
      weight: Double = 0,
      characters: Int = 0,
      contentClass: ContentClass = .prose,
      reportedTokens: Int? = nil,
      item: Item? = nil
    ) {
      self.band = band
      self.label = label
      self.weight = weight
      self.characters = characters
      self.contentClass = contentClass
      self.reportedTokens = reportedTokens
      self.item = item
    }

    public var isShare: Bool { reportedTokens == nil && characters == 0 }
  }

  public struct Plan: Sendable {
    public let parts: [Part]

    public init(parts: [Part]) {
      self.parts = parts
    }

    public var isEmpty: Bool { parts.isEmpty }
  }

  public static func priorPlan(
    observed: Set<Band> = [],
    systemLengths: [Int] = [],
    tools: [ContextReport.Tool] = []
  ) -> Plan {
    var parts: [Part] = []
    for ratio in ratios where !observed.contains(ratio.band) {
      let recorded = tools.filter { $0.isMCP == (ratio.band == .mcp) }
      switch ratio.band {
      case .sys where !systemLengths.isEmpty:
        parts += systemParts(lengths: systemLengths, total: nil)
      case .tools, .mcp:
        parts += recorded.isEmpty ? [band(ratio)] : recorded.map { toolPart($0, reported: nil) }
      default:
        parts.append(band(ratio))
      }
    }
    return Plan(parts: parts)
  }

  private static func band(_ ratio: (band: Band, share: Double)) -> Part {
    Part(band: ratio.band, label: BandRegistry.label(of: ratio.band), weight: ratio.share)
  }

  static func systemParts(lengths: [Int], total: Int?) -> [Part] {
    let shares = total.map { Normalizer.allocate(total: $0, weights: lengths.map(Double.init)) }
    return lengths.enumerated().map { index, length in
      Part(
        band: .sys,
        label: "System prompt \(index + 1)",
        characters: length,
        contentClass: .prose,
        reportedTokens: shares?[index],
        item: .systemBlock(index)
      )
    }
  }

  static func toolPart(_ tool: ContextReport.Tool, reported: Int?) -> Part {
    Part(
      band: tool.isMCP ? .mcp : .tools,
      label: tool.label,
      characters: tool.characters,
      contentClass: .json,
      reportedTokens: reported,
      item: .tool(tool)
    )
  }

  public static func segments(
    total: Int,
    observed: Set<Band> = []
  ) -> [(band: Band, label: String, tokens: Int)] {
    let parts = priorPlan(observed: observed).parts
    let sizes = Normalizer.allocate(total: total, weights: parts.map(\.weight))
    return zip(parts, sizes).map { ($0.band, $0.label, $1) }
  }
}
