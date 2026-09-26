internal import ScopeCore

public struct StatusReading: Sendable, Equatable {
  public let isLive: Bool
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
