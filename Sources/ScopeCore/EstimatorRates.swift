/// Tokens per character per content class, plus the framing the harness adds
/// and the transcript never shows.
///
/// The rates are deliberately not a tokenizer. They predict the derived token
/// delta between two requests, so they also carry what never appears in the
/// transcript. See `docs/TRANSCRIPT_FORMAT.md` section 9.
///
/// That hidden framing is charged per request, not per block. Charging it per
/// block made a 50 character reminder come out at 82 tokens, which is not a
/// statement about that reminder, it is a statement about the turn it arrived
/// in. It is now a segment of its own, so it can be seen and argued with.
public struct EstimatorRates: Sendable, Codable, Hashable {
  /// A content block costs its delimiters and a role header. Small, fixed,
  /// and not fitted: the fit cannot tell it apart from the per-request term,
  /// and letting it try is what put the framing on the wrong segments.
  public static let tokensPerBlock = 8.0

  public var tokensPerCharacter: [ContentClass: Double]
  /// What the harness injects per request and never writes down: system
  /// reminders, tool result framing, the rest of the turn scaffolding.
  public var tokensPerRequest: Double
  /// How many derived deltas the rates were fitted against. Zero means the
  /// prior is still in use.
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

  /// Fitted over 4666 derived deltas of real sessions on the build machine,
  /// weighted for relative error, with the per-block cost held at 8.
  /// `ctxscope calibrate` reproduces it from whatever sessions are at hand.
  /// Characters per token: prose 2.84, code 3.05, json 2.63, image 220.
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

  /// Estimated size of one content block.
  public func estimate(characters: Int, contentClass: ContentClass) -> Double {
    Double(characters) * rate(for: contentClass) + Self.tokensPerBlock
  }

  /// Characters per token, the way the numbers are usually quoted.
  public func charactersPerToken(_ contentClass: ContentClass) -> Double {
    let rate = rate(for: contentClass)
    return rate > 0 ? 1.0 / rate : 0
  }
}

/// One derived delta: what was appended between two requests, and what it
/// cost. The fit runs on these.
public struct EstimatorSample: Sendable, Hashable {
  public var characters: [ContentClass: Int]
  public var blocks: Int
  /// Tokens the delta cost, after measured output was subtracted.
  public var tokens: Int

  public init(characters: [ContentClass: Int], blocks: Int, tokens: Int) {
    self.characters = characters
    self.blocks = blocks
    self.tokens = tokens
  }
}
