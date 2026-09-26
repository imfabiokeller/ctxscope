public import CoreGraphics

extension Theme {
  /// The areas things are drawn on, from the window down to a code box.
  public struct SurfaceRoles: Sendable, Hashable, Codable {
    /// The window's main column and the summary cards on it.
    public let window: ThemeColor
    /// The bar across the top of the window.
    public let header: ThemeColor
    /// The fixed column on the window's right.
    public let sidebar: ThemeColor
    /// A card or a button face that stands on the sidebar or the window.
    public let raised: ThemeColor
    /// The row that is selected in a table.
    public let selection: ThemeColor
    /// The box a block's text is shown in.
    public let code: ThemeColor
    /// A short command set in a line of prose, such as `/ctxscope`.
    public let inlineCode: ThemeColor
    /// The menu bar popover's panel.
    public let popover: ThemeColor
    /// The bar of buttons at the bottom of the popover.
    public let popoverFooter: ThemeColor
    /// A fact's tile in a sidebar: a solid chip with no border, the prompt
    /// bands' look.
    public let tile: ThemeColor
  }

  /// Lines, from the strongest border to the faintest row rule.
  public struct LineRoles: Sendable, Hashable, Codable {
    /// Under the header, beside the sidebar, above and below a table header.
    public let hairline: ThemeColor
    /// Between groups inside a panel.
    public let divider: ThemeColor
    /// Between the rows of a table.
    public let row: ThemeColor
    /// Around a card and a code box.
    public let card: ThemeColor
    /// Around a pop-up button in the window's header.
    public let toolbarControl: ThemeColor
    /// Around a push button and a search field.
    public let control: ThemeColor
    /// Around the popover's panel.
    public let popover: ThemeColor
  }

  /// A shadow as an offset and a blur, the way most design tools write it,
  /// rather than SwiftUI's radius.
  public struct ShadowRole: Sendable, Hashable, Codable {
    public let color: ThemeColor
    public let x: CGFloat
    public let y: CGFloat
    /// The blur. SwiftUI's radius is half of it.
    public let blur: CGFloat

    public var radius: CGFloat { blur / 2 }
  }

  public struct ShadowRoles: Sendable, Hashable, Codable {
    /// Under the selected item of a segmented picker.
    public let thumb: ShadowRole
    /// Under the popover's panel.
    public let popover: ShadowRole
  }
}
