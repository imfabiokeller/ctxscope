internal import Foundation
internal import ScopeCore

/// The popover's content, from what the model holds now.
///
/// The popover shows the latest request. The model already holds the lane's
/// analyses and the figures at the playhead, which is the latest request
/// unless somebody moved it; only then are the figures worked out again for
/// the latest one. The popover asks when it opens and when the model changes
/// under it, never on a timer.
@MainActor
public enum PopoverSource {
  public static func content(
    of model: InstrumentModel, context: PopoverPresenter.Context
  ) -> PopoverContent {
    let sessions = model.list.entries
    let empty = PopoverContent.empty(PopoverPresenter.empty(sessions: sessions, context: context))
    guard let analysis = model.analysis, let recording = model.recording else { return empty }
    let last = analysis.lastRequest
    let figures =
      model.figures.flatMap { $0.request == last ? $0 : nil } ?? analysis.figures(at: last)
    let focused = PopoverPresenter.focused(
      session: PopoverPresenter.Session(
        id: recording.sessionID, title: recording.title, project: recording.project),
      lane: analysis.lane, tally: analysis.tally, costs: analysis.costs, cache: analysis.cache,
      unused: figures.unused,
      isLive: model.liveness.isLive, sessions: sessions, context: context)
    return focused.map(PopoverContent.focused) ?? empty
  }
}
