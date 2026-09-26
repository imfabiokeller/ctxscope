public import ScopeCore

extension Theme {
  public struct KindRoles: Sendable, Hashable, Codable {
    public let system: ThemeColor
    public let tools: ThemeColor
    public let memory: ThemeColor
    public let you: ThemeColor
    public let agent: ThemeColor
    public let results: ThemeColor

    public var inReadingOrder: [ThemeColor] { [system, tools, memory, you, agent, results] }

    public var named: [(name: String, color: ThemeColor)] {
      Array(zip(["system", "tools", "memory", "you", "agent", "results"], inReadingOrder))
    }

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

  public struct ChartRoles: Sendable, Hashable, Codable {
    public let track: ThemeColor
    public let meterTrack: ThemeColor
    public let blockGap: ThemeColor
    public let gridStrong: ThemeColor
    public let gridFaint: ThemeColor
    public let marker: ThemeColor
    public let bracket: ThemeColor
    public let phase: ThemeColor
    public let phaseSelected: ThemeColor
    public let phaseInk: ThemeColor
    public let phaseInkSelected: ThemeColor
    public let cost: ThemeColor
    public let costBreak: ThemeColor
    public let spark: ThemeColor
    public let sparkBreak: ThemeColor
    public let dimmedOpacity: Double
  }

  // Only the snapshots draw these; in the app the system does.
  public struct ChromeRoles: Sendable, Hashable, Codable {
    public let windowBorder: ThemeColor
    public let close: ThemeColor
    public let minimize: ThemeColor
    public let zoom: ThemeColor
    public let desktop: ThemeColor
    public let menuBar: ThemeColor
  }
}
