public import CoreGraphics

/// The Connect panel: its window, its inset and the room between its parts.
extension Metrics {
  public var connect: Connect { Connect() }

  public struct Connect: Sendable, Hashable {
    public init() {}
    public let size = CGSize(width: 520, height: 460)
    public let padding: CGFloat = 16
    /// Between the tiles, the notes and the diff.
    public let gap: CGFloat = 12
    /// Between two notes.
    public let noteGap: CGFloat = 4
  }
}
