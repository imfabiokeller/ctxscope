internal import ScopeCore

/// The "Context per request" chart from a lane's reading order, costs and
/// cache breaks.
enum TimelineChartPresenter {
  static func chart(
    lane: Lane, costs: CostAnalysis, cache: CacheAnalysis, order: ReadingOrder,
    names: BlockNames, highlighted: ClosedRange<Int>?
  ) -> TimelineChart {
    var index: [SegmentID: Int] = [:]
    let blocks = lane.segments.enumerated().map { slot, segment in
      index[segment.id] = slot
      return TimelineChart.Block(
        label: names.name(of: segment), kind: segment.kind, size: UIFormat.tokens(segment.tokens))
    }
    let count = min(order.requestCount, costs.perRequest.count)
    var identity = Hasher()
    identity.combine(lane.id.rawValue)
    identity.combine(blocks.count)
    let columns = (0..<count).map { request in
      let column = order.column(at: request)
      identity.combine(column.end)
      return TimelineChart.Column(
        slices: column.slices.map {
          TimelineChart.Slice(block: index[$0.segment] ?? 0, start: $0.start, tokens: $0.tokens)
        },
        title: MagnifierWords.request(request),
        figures: MagnifierWords.figures(
          tokens: column.end, dollars: costs.perRequest[request].context))
    }
    let scale = max(lane.window.tokens, columns.map(\.end).max() ?? 0, 1)
    identity.combine(scale)
    let broken = Set(cache.busts.map(\.request))
    let dearest = costs.perRequest.prefix(count).map(\.context).max() ?? 0
    return TimelineChart(
      identity: identity.finalize(),
      scale: scale,
      blocks: blocks,
      columns: columns,
      breaks: cache.busts.enumerated().compactMap { number, bust in
        bust.request < count ? TimelineChart.Break(column: bust.request, number: number + 1) : nil
      },
      costs: costs.perRequest.prefix(count).map {
        TimelineChart.Cost(
          share: dearest > 0 ? $0.context / dearest : 0, isBreak: broken.contains($0.request))
      },
      tokenTicks: TimelineChart.tokenTicks(scale),
      requestTicks: TimelineChart.requestTicks(count),
      highlighted: highlighted
    )
  }
}
