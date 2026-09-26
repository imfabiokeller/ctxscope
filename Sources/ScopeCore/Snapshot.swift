/// One request and everything measured about it.

/// The `usage` block of one API call, as the harness recorded it.
public struct RequestUsage: Sendable, Codable, Hashable {
  public var inputTokens: Int
  public var cacheReadTokens: Int
  public var cacheCreationTokens: Int
  public var outputTokens: Int
  public var thinkingTokens: Int
  public var ephemeral1hTokens: Int
  public var ephemeral5mTokens: Int
  /// How many attempts the API made for this call. Two means a fallback: the
  /// aggregate usage is then assembled from both attempts, which is why its
  /// fields can disagree with each other.
  public var iterations: Int
  /// The models those attempts used, when there was more than one.
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

  /// Everything the model read for this call. The M value every segment sum
  /// is normalized to.
  public var promptTotal: Int {
    inputTokens + cacheReadTokens + cacheCreationTokens
  }

  /// Share of the prompt that came out of the cache.
  public var cacheHit: Double {
    let denominator = cacheReadTokens + cacheCreationTokens + inputTokens
    guard denominator > 0 else { return 0 }
    return Double(cacheReadTokens) / Double(denominator)
  }

  /// Output tokens that were not thinking.
  public var visibleOutputTokens: Int {
    max(0, outputTokens - thinkingTokens)
  }

  /// Everything that was in the cache after this call.
  public var cachedAfter: Int {
    cacheReadTokens + cacheCreationTokens
  }
}

/// All segments of one request with their measurements.
public struct Snapshot: Sendable, Codable, Hashable {
  /// Position in the lane, 0-based. The unit of time.
  public let index: Int
  /// The harness `requestId`, when it had one.
  public let requestID: String?
  /// Seconds since 1970, kept as a plain number so ScopeCore stays free of
  /// date formatting decisions.
  public let timestamp: Double
  public let model: String
  public let usage: RequestUsage
  /// The request this one continued from. Normally the one before it, but a
  /// rewind or a compaction makes it something else, and the cache has to be
  /// compared against the right one.
  public let parentRequest: Int?
  /// How far the estimator was off for this request, before normalization,
  /// in tokens. Signed: positive means it estimated too much. It is what the
  /// estimator's calibration learns from.
  public let residualTokens: Int
  /// Tokens that entered the context at this request. The denominator the
  /// residual is read against.
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

  /// Residual as a share of what entered at this request. This is the
  /// estimator's own error against a derived value.
  public var estimatorResidual: Double {
    appendedTokens > 0 ? Double(abs(residualTokens)) / Double(appendedTokens) : 0
  }

  public var measuredTotal: Tokens { Tokens(usage.promptTotal, .measured) }
}

/// A compaction, as the harness reported it.
public struct CompactionEvent: Sendable, Codable, Hashable {
  /// The request index the compaction takes effect before.
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
