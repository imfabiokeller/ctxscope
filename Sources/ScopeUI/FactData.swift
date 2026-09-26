public import ScopeCore

/// One fact a sidebar shows on a tile: what it is, its value on one line,
/// and a quieter line of detail under it. Both sidebars write their facts as
/// these and draw them with `FactGrid`.
public struct FactData: Sendable, Hashable, Identifiable {
  /// A block's kind, whose swatch leads the value, for a fact about a block.
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
  /// A figure at the tile's far end, such as a block's size.
  public let trailing: String?
  /// Whether the tile takes both columns of the grid.
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
