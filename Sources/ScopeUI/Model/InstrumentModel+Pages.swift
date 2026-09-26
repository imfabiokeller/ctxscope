public import ScopeCore

public enum WindowPage: String, Sendable, CaseIterable, Hashable {
  case context = "Context"
  case timeline = "Timeline"
}

struct TimelineKey: Equatable {
  let generation: Int
  let selectedPrompt: Int?
  let promptLines: [SegmentID: String]
  let names: BlockNames
}

extension InstrumentModel {
  public func showInTimeline(block: SegmentID) {
    guard let analysis, let segment = analysis.segment(block) else { return }
    page = .timeline
    if selection != block { select(block) }
    selectedPrompt = analysis.prompts.prompt(containing: segment.born)?.number
  }

  public func showContext(at request: Int) {
    page = .context
    move(playheadTo: request)
  }

  public func timelineData() -> TimelineData? {
    guard let analysis else { return nil }
    let key = TimelineKey(
      generation: generation, selectedPrompt: selectedPrompt, promptLines: promptLines,
      names: blockNames)
    if let timeline, timeline.key == key { return timeline.data }
    let data = TimelinePresenter.present(
      lane: analysis.lane, costs: analysis.costs, cache: analysis.cache,
      prompts: analysis.prompts, order: analysis.readingOrder, promptLines: promptLines,
      names: blockNames, selectedPrompt: selectedPrompt)
    timeline = (key, data)
    return data
  }

  func loadTranscriptWords() {
    let host = host
    let lane = lane
    lines?.cancel()
    lines = Task { [weak self] in
      let found = await host.promptLines(lane: lane)
      let details = await host.blockDetails(lane: lane)
      guard let self else { return }
      defer { lines = nil }
      guard !Task.isCancelled, self.lane == lane else { return }
      promptLines = found
      blockNames = BlockNames(details)
    }
  }
}
