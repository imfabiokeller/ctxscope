/// Something that happened to a lane's context, with the provenance of the
/// claim. Events the harness wrote down carry grade D. Events ctxscope only
/// infers from the measured totals carry grade E and say so.
public struct LaneEvent: Sendable, Codable, Hashable {
  public enum Kind: String, Sendable, Codable, CaseIterable {
    /// The harness recorded a compaction.
    case compaction
    /// Content left the context with nothing in the transcript saying so.
    case inferredRetirement
    /// The model changed mid-lane. The prefix and the cache change with it.
    case modelSwitch
    /// The cache read dropped below what the previous request had cached.
    case cacheBust
    /// A subagent returned, and its whole result entered this lane at once.
    case subagentReturn

    /// Which event a request is named after when several happened at it. A
    /// compaction says more about the context than a bust that followed from
    /// it.
    public var weight: Int {
      switch self {
      case .compaction: 0
      case .modelSwitch: 1
      case .subagentReturn: 2
      case .inferredRetirement: 3
      case .cacheBust: 4
      }
    }
  }

  public let request: Int
  public let kind: Kind
  /// Tokens the event moved, when that is meaningful.
  public let tokens: Tokens
  /// One short neutral line. Never content.
  public let detail: String

  public init(request: Int, kind: Kind, tokens: Tokens, detail: String) {
    self.request = request
    self.kind = kind
    self.tokens = tokens
    self.detail = detail
  }
}
