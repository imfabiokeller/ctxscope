/// What tokens cost, as data. The one place a price is written down: every
/// dollar figure in the window, the menu bar and the CLI is worked out from
/// this table.

/// The four prices one request is billed at, in dollars per million tokens.
public struct Prices: Sendable, Codable, Hashable {
  /// Writing a token to the cache.
  public let cacheWrite: Double
  /// Reading a token back out of the cache.
  public let cacheRead: Double
  /// Sending a token with no cache involved.
  public let input: Double
  public let output: Double

  public init(cacheWrite: Double, cacheRead: Double, input: Double, output: Double) {
    self.cacheWrite = cacheWrite
    self.cacheRead = cacheRead
    self.input = input
    self.output = output
  }

  public func reading(_ tokens: Int) -> Double { Self.dollars(tokens, cacheRead) }
  public func writing(_ tokens: Int) -> Double { Self.dollars(tokens, cacheWrite) }
  public func sendingUncached(_ tokens: Int) -> Double { Self.dollars(tokens, input) }
  public func producing(_ tokens: Int) -> Double { Self.dollars(tokens, output) }

  /// What writing tokens to the cache again costs beyond reading them, which
  /// is what a cache break adds.
  public func rewriteExtra(_ tokens: Int) -> Double {
    Self.dollars(tokens, cacheWrite - cacheRead)
  }

  private static func dollars(_ tokens: Int, _ perMillion: Double) -> Double {
    Double(tokens) * perMillion / 1_000_000
  }
}

/// Prices per model, matched on the start of the model id, with one entry for
/// every model the table does not name.
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

  /// The prices of the entry whose prefix matches most of the model id, so a
  /// narrower entry wins over a broader one whatever order they were listed
  /// in.
  public func prices(for model: String) -> Prices {
    entries
      .filter { model.hasPrefix($0.modelPrefix) }
      .max { $0.modelPrefix.count < $1.modelPrefix.count }?
      .prices ?? fallback
  }

  /// One table for every model. Per model prices are not written down yet,
  /// and none is invented here, so every model is billed at these; the
  /// limitation is listed in `docs/HOW_IT_MEASURES.md`.
  public static let standard = PriceTable(
    entries: [],
    fallback: Prices(cacheWrite: 20, cacheRead: 0.25, input: 10, output: 50)
  )
}
