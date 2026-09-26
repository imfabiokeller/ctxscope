public import ScopeCore

public struct PlayheadFigures: Sendable {
  public let request: Int
  public let column: ReadingOrder.Column
  public let blockCosts: BlockCostAnalysis
  public let unused: UnusedSummary
  public let toolGroups: [ToolGroup]
  public let tally: RequestTally?
  public let cost: RequestCost?

  init(analysis: LaneAnalysis, request: Int) {
    let lane = analysis.lane
    self.request = request
    column = analysis.readingOrder.column(at: request)
    let blockCosts = BlockCostAnalyzer.run(
      lane, cache: analysis.segmentCache, costs: analysis.costs, upTo: request)
    self.blockCosts = blockCosts
    unused = UseAnalyzer.unused(
      lane, findings: analysis.findings, costs: blockCosts, at: request)
    toolGroups = ToolGroupAnalyzer.run(lane, findings: analysis.findings, at: request)
    tally = analysis.tally(at: request)
    let costs = analysis.costs.perRequest
    cost = request < costs.count ? costs[request] : nil
  }
}
