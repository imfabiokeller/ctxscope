internal import ScopeCore

/// Everything the menu bar item shows of the session in focus, taken from
/// the analysis the window shows.
///
/// It is a value, and it is `Equatable`, so the status item can tell one state
/// of the world from the next without a second pipeline: the same
/// `InstrumentModel`, the same `LaneAnalysis`, the same analyzers.
public struct StatusReading: Sendable, Equatable {
  public let isLive: Bool
  /// The context at the latest request, and the window it is measured
  /// against.
  public let totalTokens: Int
  public let window: Int

  public init(isLive: Bool, totalTokens: Int, window: Int) {
    self.isLive = isLive
    self.totalTokens = totalTokens
    self.window = window
  }

  @MainActor
  public static func make(from model: InstrumentModel) -> StatusReading? {
    guard let analysis = model.analysis, model.recording != nil, analysis.requestCount > 0
    else { return nil }
    return StatusReading(
      isLive: model.liveness.isLive,
      totalTokens: analysis.tally(at: analysis.lastRequest)?.total.value ?? 0,
      window: analysis.lane.window.tokens)
  }
}
