public import CoreGraphics

/// The sizes of a fact tile and the grid of them the sidebars set their facts
/// in, and of the chip a prompt's number stands on at the top of its detail.
extension Metrics {
  public var tile: Tile { Tile() }

  public struct Tile: Sendable, Hashable {
    public init() {}
    public let padding = Insets(vertical: 10, horizontal: 12)
    public let radius: CGFloat = 8
    /// Between two tiles of a row, and between the rows.
    public let gap: CGFloat = 8
    /// Under the label, and between the value and its detail.
    public let labelGap: CGFloat = 3
    public let detailGap: CGFloat = 1
    /// Between a swatch, the value and the figure at the far end.
    public let valueGap: CGFloat = 8
    /// The chip a prompt's number stands on: its height, and either side of
    /// the number.
    public let chipHeight: CGFloat = 22
    public let chipInset: CGFloat = 8
    /// Between the chip and the requests beside it, and the prompt's text
    /// under them.
    public let headerGap: CGFloat = 8
    /// The most lines a prompt's text takes.
    public let promptLines = 3
  }
}
