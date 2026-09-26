public struct RequestUsage: Sendable, Codable, Hashable {
  public var inputTokens: Int
  public var cacheReadTokens: Int
  public var cacheCreationTokens: Int
  public var outputTokens: Int
  public var thinkingTokens: Int
  public var ephemeral1hTokens: Int
  public var ephemeral5mTokens: Int
  /// Two means a fallback: usage is aggregated from both attempts, so its
  /// fields can disagree.
  public var iterations: Int
  public var iterationModels: [String]

  public init(
    inputTokens: Int = 0,
    cacheReadTokens: Int = 0,
    cacheCreationTokens: Int = 0,
    outputTokens: Int = 0,
    thinkingTokens: Int = 0,
    ephemeral1hTokens: Int = 0,
    ephemeral5mTokens: Int = 0,
    iterations: Int = 1,
    iterationModels: [String] = []
  ) {
    self.inputTokens = inputTokens
    self.cacheReadTokens = cacheReadTokens
    self.cacheCreationTokens = cacheCreationTokens
    self.outputTokens = outputTokens
    self.thinkingTokens = thinkingTokens
    self.ephemeral1hTokens = ephemeral1hTokens
    self.ephemeral5mTokens = ephemeral5mTokens
    self.iterations = iterations
    self.iterationModels = iterationModels
  }

  public var promptTotal: Int {
    inputTokens + cacheReadTokens + cacheCreationTokens
  }

  public var cacheHit: Double {
    let denominator = cacheReadTokens + cacheCreationTokens + inputTokens
    guard denominator > 0 else { return 0 }
    return Double(cacheReadTokens) / Double(denominator)
  }

  public var visibleOutputTokens: Int {
    max(0, outputTokens - thinkingTokens)
  }

  public var cachedAfter: Int {
    cacheReadTokens + cacheCreationTokens
  }
}

public struct Snapshot: Sendable, Codable, Hashable {
  public let index: Int
  public let requestID: String?
  /// Seconds since 1970.
  public let timestamp: Double
  public let model: String
  public let usage: RequestUsage
  public let parentRequest: Int?
  /// Estimator error before normalization. Positive means it estimated too much.
  public let residualTokens: Int
  public let appendedTokens: Int

  public init(
    index: Int,
    requestID: String?,
    timestamp: Double,
    model: String,
    usage: RequestUsage,
    parentRequest: Int? = nil,
    residualTokens: Int = 0,
    appendedTokens: Int = 0
  ) {
    self.index = index
    self.requestID = requestID
    self.timestamp = timestamp
    self.model = model
    self.usage = usage
    self.parentRequest = parentRequest
    self.residualTokens = residualTokens
    self.appendedTokens = appendedTokens
  }

  public var estimatorResidual: Double {
    appendedTokens > 0 ? Double(abs(residualTokens)) / Double(appendedTokens) : 0
  }

  public var measuredTotal: Tokens { Tokens(usage.promptTotal, .measured) }
}

public struct CompactionEvent: Sendable, Codable, Hashable {
  public let atRequest: Int
  public let trigger: String
  public let preTokens: Int
  public let postTokens: Int
  public let droppedTokens: Int

  public init(
    atRequest: Int,
    trigger: String,
    preTokens: Int,
    postTokens: Int,
    droppedTokens: Int
  ) {
    self.atRequest = atRequest
    self.trigger = trigger
    self.preTokens = preTokens
    self.postTokens = postTokens
    self.droppedTokens = droppedTokens
  }
}
