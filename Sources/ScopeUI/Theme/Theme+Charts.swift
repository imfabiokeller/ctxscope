public import ScopeCore

extension Theme {
  /// The six kinds a block can be, one color each, in the order the model
  /// reads them. The three the harness sends with every request are greys,
  /// darkest first; the three the conversation adds have a hue each.
  public struct KindRoles: Sendable, Hashable, Codable {
    public let system: ThemeColor
    public let tools: ThemeColor
    public let memory: ThemeColor
    public let you: ThemeColor
    public let agent: ThemeColor
    public let results: ThemeColor

    /// All six, in reading order.
    public var inReadingOrder: [ThemeColor] { [system, tools, memory, you, agent, results] }

    /// All six with the word the UI uses for each, in reading order.
    public var named: [(name: String, color: ThemeColor)] {
      Array(zip(["system", "tools", "memory", "you", "agent", "results"], inReadingOrder))
    }

    /// The color of one kind.
    public func color(of kind: Kind) -> ThemeColor {
      switch kind {
      case .system: system
      case .tools: tools
      case .memory: memory
      case .you: you
      case .agent: agent
      case .results: results
      }
    }
  }

  /// What the charts are drawn with, apart from the kind colors.
  public struct ChartRoles: Sendable, Hashable, Codable {
    /// Behind the context bar, where the window is not yet filled.
    public let track: ThemeColor
    /// Behind the popover's small fill bar.
    public let meterTrack: ThemeColor
    /// The one point line between two blocks of the context bar.
    public let blockGap: ThemeColor
    /// The top and bottom lines of a plot.
    public let gridStrong: ThemeColor
    /// The lines between them.
    public let gridFaint: ThemeColor
    /// Anything drawn over the data to point at it: the selected block's
    /// outline, a cache break's line, the cached-up-to mark.
    public let marker: ThemeColor
    /// The bracket over what is sent with every request.
    public let bracket: ThemeColor
    /// A prompt's button above the timeline, and the selected one.
    public let phase: ThemeColor
    public let phaseSelected: ThemeColor
    public let phaseInk: ThemeColor
    public let phaseInkSelected: ThemeColor
    /// A request's cost bar, and the bar of a request that sent the cache
    /// again.
    public let cost: ThemeColor
    public let costBreak: ThemeColor
    /// The popover's context-per-request bars, and a cache break among them.
    public let spark: ThemeColor
    public let sparkBreak: ThemeColor
    /// How far a request outside the selected prompt fades.
    public let dimmedOpacity: Double
  }

  /// What the system draws around a window and above a popover. The app never
  /// draws these: only the snapshots do, so a picture looks the way the
  /// window and the popover look on screen.
  public struct ChromeRoles: Sendable, Hashable, Codable {
    public let windowBorder: ThemeColor
    public let close: ThemeColor
    public let minimize: ThemeColor
    public let zoom: ThemeColor
    /// The desktop behind the popover.
    public let desktop: ThemeColor
    public let menuBar: ThemeColor
  }
}
