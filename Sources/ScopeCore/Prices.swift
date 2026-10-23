public struct Prices: Sendable, Codable, Hashable {
  public let cacheWrite5m: Double
  public let cacheWrite1h: Double
  public let cacheRead: Double
  public let input: Double
  public let output: Double

  public init(
    cacheWrite5m: Double, cacheWrite1h: Double, cacheRead: Double, input: Double, output: Double
  ) {
    self.cacheWrite5m = cacheWrite5m
    self.cacheWrite1h = cacheWrite1h
    self.cacheRead = cacheRead
    self.input = input
    self.output = output
  }

  public func reading(_ tokens: Int) -> Double { Self.dollars(tokens, cacheRead) }
  public func sendingUncached(_ tokens: Int) -> Double { Self.dollars(tokens, input) }
  public func producing(_ tokens: Int) -> Double { Self.dollars(tokens, output) }

  public func writing(_ tokens: Int, oneHour: Bool) -> Double {
    Self.dollars(tokens, oneHour ? cacheWrite1h : cacheWrite5m)
  }

  /// Written tokens the API split by lifetime; tokens outside the split are billed at the
  /// five-minute price, the API's default lifetime.
  public func writing(_ tokens: Int, oneHour: Int, fiveMinute: Int) -> Double {
    let long = min(max(oneHour, 0), tokens)
    let short = tokens - long
    return Self.dollars(long, cacheWrite1h) + Self.dollars(short, cacheWrite5m)
  }

  public func rewriteExtra(_ tokens: Int, oneHour: Bool) -> Double {
    Self.dollars(tokens, (oneHour ? cacheWrite1h : cacheWrite5m) - cacheRead)
  }

  private static func dollars(_ tokens: Int, _ perMillion: Double) -> Double {
    Double(tokens) * perMillion / 1_000_000
  }
}

public struct PriceTable: Sendable, Codable, Hashable {
  public struct Entry: Sendable, Codable, Hashable {
    public let modelPrefix: String
    public let prices: Prices

    public init(modelPrefix: String, prices: Prices) {
      self.modelPrefix = modelPrefix
      self.prices = prices
    }
  }

  public let entries: [Entry]
  public let fallback: Prices

  public init(entries: [Entry], fallback: Prices) {
    self.entries = entries
    self.fallback = fallback
  }

  public func prices(for model: String) -> Prices {
    entries
      .filter { model.hasPrefix($0.modelPrefix) }
      .max { $0.modelPrefix.count < $1.modelPrefix.count }?
      .prices ?? fallback
  }

  /// USD per million tokens from platform.claude.com/docs/en/about-claude/pricing, read on
  /// 2026-10-23. A model id matches its longest prefix, so "claude-opus-5-5[1m]" is Opus 5.5
  /// and "claude-opus-5" is Opus 5. An unknown model is billed as Claude Fable 5.1, the most
  /// expensive current model. Claude Haiku 5.5 is billed at its rate for prompts up to
  /// 100,000 tokens; the API charges five times that above 100,000.
  public static let standard = PriceTable(
    entries: rows(["claude-fable-5-1", "claude-mythos-5-1"], 10, 12.5, 20, 0.25, 50)
      + rows(["claude-fable-5", "claude-mythos-5"], 10, 12.5, 20, 1, 50)
      + rows(["claude-opus-5-5"], 4, 5, 8, 0.20, 20)
      + rows(
        [
          "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
          "claude-opus-4-5",
        ], 5, 6.25, 10, 0.50, 25)
      + rows(["claude-opus-4-1", "claude-opus-4"], 15, 18.75, 30, 1.50, 75)
      + rows(["claude-sonnet-5-5"], 2, 2.5, 4, 0.10, 10)
      + rows(["claude-sonnet-5"], 2, 2.5, 4, 0.20, 10)
      + rows(["claude-sonnet-4-6", "claude-sonnet-4-5", "claude-sonnet-4"], 3, 3.75, 6, 0.30, 15)
      + rows(["claude-haiku-5-5"], 0.10, 0.125, 0.20, 0.01, 0.50)
      + rows(["claude-haiku-4-5"], 1, 1.25, 2, 0.10, 5)
      + rows(["claude-3-5-haiku"], 0.80, 1, 1.60, 0.08, 4),
    fallback: Prices(cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 0.25, input: 10, output: 50)
  )

  /// Prefixes that share one price row, in the pricing page's column order: input, five-minute
  /// write, one-hour write, cache read, output.
  private static func rows(
    _ prefixes: [String], _ input: Double, _ write5m: Double, _ write1h: Double,
    _ read: Double, _ output: Double
  ) -> [Entry] {
    let prices = Prices(
      cacheWrite5m: write5m, cacheWrite1h: write1h, cacheRead: read, input: input, output: output)
    return prefixes.map { Entry(modelPrefix: $0, prices: prices) }
  }
}
