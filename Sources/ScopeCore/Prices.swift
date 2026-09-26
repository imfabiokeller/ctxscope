public struct Prices: Sendable, Codable, Hashable {
  public let cacheWrite: Double
  public let cacheRead: Double
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

  public func rewriteExtra(_ tokens: Int) -> Double {
    Self.dollars(tokens, cacheWrite - cacheRead)
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

  /// No per model prices are written down yet, so every model is billed at these.
  public static let standard = PriceTable(
    entries: [],
    fallback: Prices(cacheWrite: 20, cacheRead: 0.25, input: 10, output: 50)
  )
}
