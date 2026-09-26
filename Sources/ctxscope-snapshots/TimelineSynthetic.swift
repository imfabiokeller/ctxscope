import ScopeCore
import ScopeUI

/// The Timeline page as the presenter makes it from the synthetic 200k
/// recording: a compaction, a cache break, and a prompt every few requests.
enum TimelineSynthetic {
  /// Which prompt is selected in the picture.
  static let selected = 3

  static func data() -> TimelineData {
    // The synthetic recording is one lane, the main one.
    present(SyntheticRecording.make().lanes[0])
  }

  private static func present(_ lane: Lane) -> TimelineData {
    let costs = CostAnalyzer.run(lane)
    let cache = CacheAnalyzer.run(lane)
    // The synthetic prompts have no text; their labels stand in for the
    // first lines a session would have.
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
