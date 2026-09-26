extension Theme {
  /// Text, darkest first. Every one of these but `disabled` holds 4.5:1 on
  /// the surfaces it is set on, and a test checks it in both appearances.
  public struct TextRoles: Sendable, Hashable, Codable {
    public let primary: ThemeColor
    /// Supporting text a step lighter than primary: the header's summary, a
    /// card's place, the popover's legend.
    public let supporting: ThemeColor
    /// Labels, column headers, detail lines.
    public let secondary: ThemeColor
    /// The quietest text: the second half of a pop-up button's title and the
    /// search field's glass.
    public let tertiary: ThemeColor
    /// A control that cannot be used right now.
    public let disabled: ThemeColor
    /// A block's text in the code box.
    public let code: ThemeColor
    /// The word "no" in a table's Used column.
    public let unused: ThemeColor
    public let link: ThemeColor
    public let linkPressed: ThemeColor
    /// Text on the accent fill of a primary button.
    public let onAccent: ThemeColor
    /// Something that went wrong, in its own words: a settings file that
    /// could not be written.
    public let failure: ThemeColor
  }

  /// The faces of controls.
  public struct ControlRoles: Sendable, Hashable, Codable {
    /// A push button's and a pop-up button's face.
    public let fill: ThemeColor
    /// Laid over a face while it is pressed.
    public let pressed: ThemeColor
    /// The groove a segmented picker's items sit in.
    public let track: ThemeColor
    /// The selected item of a segmented picker.
    public let thumb: ThemeColor
    /// A primary button's face.
    public let accent: ThemeColor
    public let accentPressed: ThemeColor
    /// Drawn around a control that has keyboard focus.
    public let focusRing: ThemeColor
  }

  /// Small marks that state something: a session being written, a numbered
  /// event.
  public struct StatusRoles: Sendable, Hashable, Codable {
    public let liveFill: ThemeColor
    public let liveInk: ThemeColor
    public let liveDot: ThemeColor
    /// A number in a circle, such as a cache break's.
    public let badge: ThemeColor
    public let onBadge: ThemeColor
  }
}
