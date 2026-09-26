internal import Foundation
internal import ScopeCore
public import SwiftUI

public struct InstrumentView: View {
  @Bindable var model: InstrumentModel
  let onZoom: () -> Void
  let onCopy: (String) -> Void
  let stripHover: StripHover?
  @Environment(\.theme) private var theme

  public init(
    model: InstrumentModel, onZoom: @escaping () -> Void = {},
    onCopy: @escaping (String) -> Void = { _ in }, stripHover: StripHover? = nil
  ) {
    self.model = model
    self.stripHover = stripHover
    self.onZoom = onZoom
    self.onCopy = onCopy
  }

  public var body: some View {
    Group {
      if let analysis = model.analysis, let figures = model.figures {
        switch model.page {
        case .context:
          ContextPage(
            model: model, analysis: analysis, figures: figures, onCopy: onCopy,
            stripHover: stripHover
          ) {
            header {
              RequestStepper(
                position: RequestNumber.of(model.playhead), count: analysis.requestCount,
                onPrevious: { model.move(playheadTo: model.playhead - 1) },
                onNext: { model.move(playheadTo: model.playhead + 1) })
            }
          }
        case .timeline:
          if let data = model.timelineData() {
            TimelinePage(
              data: data, onSelectPrompt: { model.selectedPrompt = $0 },
              onMovePlayhead: { model.move(playheadTo: $0) },
              onShowContext: { model.showContext(at: $0) }
            ) {
              header { HeaderNote(data.headerNote) }
            }
          }
        }
      } else {
        WindowLayout {
          header { EmptyView() }
        } main: {
          empty
        } sidebar: {
          EmptyView()
        }
      }
    }
    .modifier(PlayheadKeys(model: model))
  }

  private func header(@ViewBuilder trailing: () -> some View) -> some View {
    let lanes = model.list.lanes(of: model.recording?.sessionID ?? "")
    return WindowHeader(
      session: HeaderPresenter.session(model.recording),
      sessionItems: {
        ForEach(model.list.entries) { entry in
          Button(HeaderPresenter.item(entry)) { model.focus(session: entry.id) }
        }
        // Only the focused session's file is watched, so opening the menu rescans.
        .onAppear { model.reloadSessions() }
      },
      lane: HeaderPresenter.lane(model.lane, in: lanes),
      laneItems: {
        ForEach(lanes) { lane in
          Button(HeaderPresenter.item(lane)) { model.show(lane: lane.lane) }
        }
      },
      pages: WindowPage.allCases, page: $model.page, pageTitle: \.rawValue,
      liveTitle: model.liveness.isLive ? HeaderPresenter.liveTitle : nil,
      trailing: trailing
    )
    .gesture(WindowDragGesture())
    .onTapGesture(count: 2) { onZoom() }
  }

  private var empty: some View {
    VStack(spacing: theme.metrics.contextPage.textGap) {
      Text(model.isLoading ? "Reading the session" : (model.failure ?? "No session"))
        .font(theme.type.heading)
        .foregroundStyle(theme.text.secondary.color)
      Text("Type /ctxscope in a Claude session, or pick one from the session menu.")
        .font(theme.type.caption)
        .foregroundStyle(theme.text.tertiary.color)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct ContextPage<Header: View>: View {
  let model: InstrumentModel
  let analysis: LaneAnalysis
  let figures: PlayheadFigures
  let onCopy: (String) -> Void
  let stripHover: StripHover?
  let header: Header
  @State private var filter = BlockFilter.all
  @State private var query = ""

  init(
    model: InstrumentModel, analysis: LaneAnalysis, figures: PlayheadFigures,
    onCopy: @escaping (String) -> Void, stripHover: StripHover?,
    @ViewBuilder header: () -> Header
  ) {
    self.stripHover = stripHover
    self.model = model
    self.analysis = analysis
    self.figures = figures
    self.onCopy = onCopy
    self.header = header()
  }

  var body: some View {
    let selected = model.selectedText
    let data = ContextPresenter.page(
      analysis, figures, filter: filter, query: query, selection: model.selection,
      text: selected?.segment == model.selection ? selected?.text : nil, names: model.blockNames)
    WindowLayout {
      header
    } main: {
      ContextMain(
        data: data, filter: $filter, query: $query,
        selection: Binding(get: { model.selection }, set: { model.select($0) }),
        hover: stripHover)
    } sidebar: {
      ContextSidebar(
        inspector: data.inspector, noSelection: data.noSelection,
        onShowInTimeline: { model.showInTimeline(block: $0) }, onCopy: onCopy)
    }
  }
}
