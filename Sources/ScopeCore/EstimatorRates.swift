public struct EstimatorRates: Sendable, Codable, Hashable {
  /// Fixed, not fitted: the fit cannot tell it apart from `tokensPerRequest`.
  public static let tokensPerBlock = 8.0

  public var tokensPerCharacter: [ContentClass: Double]
  public var tokensPerRequest: Double
  public var samples: Int

  public init(
    tokensPerCharacter: [ContentClass: Double],
    tokensPerRequest: Double,
    samples: Int = 0
  ) {
    self.tokensPerCharacter = tokensPerCharacter
    self.tokensPerRequest = tokensPerRequest
    self.samples = samples
  }

  /// Fitted over 4666 derived deltas of real sessions; `ctxscope calibrate` reproduces it.
  public static let prior = EstimatorRates(
    tokensPerCharacter: [
      .prose: 1.0 / 2.84,
      .code: 1.0 / 3.05,
      .json: 1.0 / 2.63,
      .image: 1.0 / 220.28,
    ],
    tokensPerRequest: 141.3
  )

  public func rate(for contentClass: ContentClass) -> Double {
    tokensPerCharacter[contentClass] ?? EstimatorRates.prior.tokensPerCharacter[contentClass]
      ?? 0.35
  }

  public func estimate(characters: Int, contentClass: ContentClass) -> Double {
    Double(characters) * rate(for: contentClass) + Self.tokensPerBlock
  }

  public func charactersPerToken(_ contentClass: ContentClass) -> Double {
    let rate = rate(for: contentClass)
    return rate > 0 ? 1.0 / rate : 0
  }
}

public struct EstimatorSample: Sendable, Hashable {
  public var characters: [ContentClass: Int]
  public var blocks: Int
  public var tokens: Int

  public init(characters: [ContentClass: Int], blocks: Int, tokens: Int) {
    self.characters = characters
    self.blocks = blocks
    self.tokens = tokens
  }
}
