extension Theme {
  // All but `disabled` must hold 4.5:1 on their surfaces; a test checks both appearances.
  public struct TextRoles: Sendable, Hashable, Codable {
    public let primary: ThemeColor
    public let supporting: ThemeColor
    public let secondary: ThemeColor
    public let tertiary: ThemeColor
    public let disabled: ThemeColor
    public let code: ThemeColor
    public let unused: ThemeColor
    public let link: ThemeColor
    public let linkPressed: ThemeColor
    public let onAccent: ThemeColor
    public let failure: ThemeColor
  }

  public struct ControlRoles: Sendable, Hashable, Codable {
    public let fill: ThemeColor
    public let pressed: ThemeColor
    public let track: ThemeColor
    public let thumb: ThemeColor
    public let accent: ThemeColor
    public let accentPressed: ThemeColor
    public let focusRing: ThemeColor
  }

  public struct StatusRoles: Sendable, Hashable, Codable {
    public let liveFill: ThemeColor
    public let liveInk: ThemeColor
    public let liveDot: ThemeColor
    public let badge: ThemeColor
    public let onBadge: ThemeColor
  }
}
