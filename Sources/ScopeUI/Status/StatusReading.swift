internal import ScopeCore

public struct StatusReading: Sendable, Equatable {
  public let isLive: Bool
  public let totalTokens: Int
  public let window: Int
  public let fill: Double
  public let breaksCache: Bool

  public init(isLive: Bool, totalTokens: Int, window: Int, fill: Double, breaksCache: Bool) {
    self.isLive = isLive
    self.totalTokens = totalTokens
    self.window = window
    self.fill = fill
    self.breaksCache = breaksCache
  }

  @MainActor
  public static func make(from model: InstrumentModel) -> StatusReading? {
    guard let analysis = model.analysis, model.recording != nil, analysis.requestCount > 0
    else { return nil }
    let last = analysis.lastRequest
    let tally = analysis.tally(at: last)
    return StatusReading(
      isLive: model.liveness.isLive,
      totalTokens: tally?.total.value ?? 0,
      window: analysis.lane.window.tokens,
      fill: tally?.fill ?? 0,
      breaksCache: analysis.cache.busts.last?.request == last)
  }
}
