public import ScopeCore

public struct FactData: Sendable, Hashable, Identifiable {
  public struct Swatch: Sendable, Hashable {
    public let kind: Kind?

    public init(_ kind: Kind?) {
      self.kind = kind
    }
  }

  public let term: String
  public let value: String
  public let detail: String?
  public let swatch: Swatch?
  public let trailing: String?
  public let isWide: Bool
  public var id: String { term }

  public init(
    _ term: String, _ value: String, detail: String? = nil, swatch: Swatch? = nil,
    trailing: String? = nil, wide: Bool = false
  ) {
    self.term = term
    self.value = value
    self.detail = detail
    self.swatch = swatch
    self.trailing = trailing
    isWide = wide
  }
}
