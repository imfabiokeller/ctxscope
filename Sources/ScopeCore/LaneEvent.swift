public struct LaneEvent: Sendable, Codable, Hashable {
  public enum Kind: String, Sendable, Codable, CaseIterable {
    case compaction
    case inferredRetirement
    case modelSwitch
    case cacheBust
    case subagentReturn

    /// Lower weight wins when several events happen at one request.
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
  public let tokens: Tokens
  /// One short neutral line. Never transcript content.
  public let detail: String

  public init(request: Int, kind: Kind, tokens: Tokens, detail: String) {
    self.request = request
    self.kind = kind
    self.tokens = tokens
    self.detail = detail
  }
}
