public import ScopeCore

/// The figures of one lane that depend on where the playhead is: the context
/// in reading order, what each block has cost so far, the unused part, and
/// the tool definitions by server.
///
/// Worked out once when the playhead moves or the lane changes. A block's
/// cost so far walks every block of the lane, and a view that asked for it
/// in its body would walk them again on every hover.
public struct PlayheadFigures: Sendable {
  /// The request these are as of, from zero.
  public let request: Int
  public let column: ReadingOrder.Column
  public let blockCosts: BlockCostAnalysis
  public let unused: UnusedSummary
  public let toolGroups: [ToolGroup]
  /// Nil only for a lane with no requests.
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
