public import ScopeCore

/// The window's two pages.
public enum WindowPage: String, Sendable, CaseIterable, Hashable {
  case context = "Context"
  case timeline = "Timeline"
}

/// What the Timeline page's data was worked out from.
struct TimelineKey: Equatable {
  let generation: Int
  let selectedPrompt: Int?
  let promptLines: [SegmentID: String]
  let names: BlockNames
}

/// Moving between the two pages, and what each needs that is not a figure.
extension InstrumentModel {
  /// Shows the timeline with the task a block entered in selected, and the
  /// block selected, so the timeline can mark it in every column.
  public func showInTimeline(block: SegmentID) {
    guard let analysis, let segment = analysis.segment(block) else { return }
    page = .timeline
    if selection != block { select(block) }
    selectedPrompt = analysis.prompts.prompt(containing: segment.born)?.number
  }

  /// Shows the context page with the playhead at a request, counted from
  /// zero like everywhere in a recording.
  public func showContext(at request: Int) {
    page = .context
    move(playheadTo: request)
  }

  /// The Timeline page's data for the lane shown, worked out once for each
  /// lane read, selected prompt, set of prompt lines and block names, and kept for every
  /// frame in between. Nil while nothing is shown.
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

  /// Reads the first line of every typed prompt of the lane shown and what
  /// every block of it did. Off the main actor, because both read the
  /// transcript, and after every change, because a live lane gains blocks.
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
