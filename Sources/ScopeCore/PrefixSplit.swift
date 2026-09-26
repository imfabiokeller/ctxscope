/// The unobserved prefix, split into blocks.
///
/// A transcript holds no tool schemas for the request itself, so the prefix
/// arrives as one derived number, and how it is divided
/// depends on what the lane recorded about it.
///
/// Three sources, in order of how much they are worth, and `Source` says which
/// one a lane used:
///
///   prior    fixed ratios, the shape of a Claude Code prompt with a handful
///            of MCP servers connected
///   snapshot a `prompt_snapshot` recorded the system prompt and the tool list
///            of the request, so SYS is one block per recorded block and TOOLS
///            and MCP are one block per tool, each sized from its own text
///   report   the harness's own `/context` run said what each category costs,
///            and what each MCP tool in it costs
///
/// A part is either sized, because something said what it costs, or a share of
/// whatever the sized parts leave. What no part accounts for becomes one
/// Unattributed block rather than being spread over blocks that did not earn
/// it.
public enum PrefixSplit {
  public static let ratios: [(band: Band, share: Double)] = [
    (.sys, 0.18),
    (.tools, 0.42),
    (.mcp, 0.30),
    (.mem, 0.10),
  ]

  /// Where a lane's prefix split came from. Recorded when the split happens,
  /// so it can never describe evidence that arrived afterwards.
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

  /// One block of the unobserved prefix, before it has a size.
  public struct Part: Sendable, Hashable {
    /// Which item of which record the text behind a part is.
    public enum Item: Sendable, Hashable {
      case systemBlock(Int)
      case tool(ContextReport.Tool)
    }

    public let band: Band
    /// Short and neutral: a band name, a tool's own name, or a numbered
    /// system prompt block.
    public let label: String
    /// Share of whatever the sized parts leave. Read only when this part has
    /// no size of its own.
    public let weight: Double
    /// Characters of the text behind this part, when the transcript recorded
    /// one. The estimator sizes the part from it when nothing else says what
    /// it costs.
    public let characters: Int
    public let contentClass: ContentClass
    /// What the harness itself said this part costs.
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

    /// True when nothing says what this part costs, so it takes a share of
    /// what the others leave.
    public var isShare: Bool { reportedTokens == nil && characters == 0 }
  }

  public struct Plan: Sendable {
    public let parts: [Part]

    public init(parts: [Part]) {
      self.parts = parts
    }

    public var isEmpty: Bool { parts.isEmpty }
  }

  /// The prior's plan, with every band the transcript recorded broken into the
  /// blocks it recorded and the rest left as shares.
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

  /// One part per recorded system prompt block. With a reported total the
  /// blocks share it by their lengths; without one each is sized from its own
  /// text.
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

  /// The prior, as sized parts. The shape every lane without a better source
  /// gets, and what the synthetic recording is built from.
  public static func segments(
    total: Int,
    observed: Set<Band> = []
  ) -> [(band: Band, label: String, tokens: Int)] {
    let parts = priorPlan(observed: observed).parts
    let sizes = Normalizer.allocate(total: total, weights: parts.map(\.weight))
    return zip(parts, sizes).map { ($0.band, $0.label, $1) }
  }
}
