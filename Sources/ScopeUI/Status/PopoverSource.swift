internal import Foundation
internal import ScopeCore

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
