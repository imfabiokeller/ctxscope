internal import ScopeCore

extension Theme {
  /// The color a block of a kind is drawn in. Unattributed tokens have no
  /// kind and are drawn as an untyped remainder, in the quiet track grey.
  func color(of kind: Kind?) -> ThemeColor {
    switch kind {
    case .system: self.kind.system
    case .tools: self.kind.tools
    case .memory: self.kind.memory
    case .you: self.kind.you
    case .agent: self.kind.agent
    case .results: self.kind.results
    case nil: chart.meterTrack
    }
  }
}
