public import CoreGraphics

extension Theme {
  public struct SurfaceRoles: Sendable, Hashable, Codable {
    public let window: ThemeColor
    public let header: ThemeColor
    public let sidebar: ThemeColor
    public let raised: ThemeColor
    public let selection: ThemeColor
    public let code: ThemeColor
    public let inlineCode: ThemeColor
    public let popover: ThemeColor
    public let popoverFooter: ThemeColor
    public let tile: ThemeColor
  }

  public struct LineRoles: Sendable, Hashable, Codable {
    public let hairline: ThemeColor
    public let divider: ThemeColor
    public let row: ThemeColor
    public let card: ThemeColor
    public let toolbarControl: ThemeColor
    public let control: ThemeColor
    public let popover: ThemeColor
  }

  // Offset and blur as design tools write them; SwiftUI's radius is half the blur.
  public struct ShadowRole: Sendable, Hashable, Codable {
    public let color: ThemeColor
    public let x: CGFloat
    public let y: CGFloat
    public let blur: CGFloat

    public var radius: CGFloat { blur / 2 }
  }

  public struct ShadowRoles: Sendable, Hashable, Codable {
    public let thumb: ShadowRole
    public let popover: ShadowRole
  }
}
