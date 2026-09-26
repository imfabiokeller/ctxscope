import ScopeCore
import ScopeUI

enum TimelineSynthetic {
  static let selected = 3

  static func data() -> TimelineData {
    present(SyntheticRecording.make().lanes[0])
  }

  private static func present(_ lane: Lane) -> TimelineData {
    let costs = CostAnalyzer.run(lane)
    let cache = CacheAnalyzer.run(lane)
    let lines = Dictionary(
      uniqueKeysWithValues: lane.segments.filter { lane.prompts.contains($0.id) }.map {
        ($0.id, $0.label)
      })
    return TimelinePresenter.present(
      lane: lane, costs: costs, cache: cache,
      prompts: PromptAnalyzer.run(lane, costs: costs, cache: cache),
      order: ReadingOrder(lane), promptLines: lines, selectedPrompt: selected)
  }
}
