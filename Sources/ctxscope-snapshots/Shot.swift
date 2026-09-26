import Foundation
import ScopeCore
import ScopeUI

/// One picture of the window or the popover, over a model built for it.
@MainActor
struct Shot {
  let name: String
  let size: CGSize
  let build: () async -> InstrumentModel

  func model() async -> InstrumentModel { await build() }

  static let windowSize = Metrics.standard.window.size
  static let popoverSize = CGSize(
    width: Metrics.standard.popover.width + 2 * Metrics.standard.hairline, height: 480)

  static var all: [Shot] {
    [
      Shot(name: "window-200k", size: windowSize) { await make(.small) },
      Shot(name: "window-1m", size: windowSize) { await make(.large) },
      // The two shortest lanes there are. One request used to fill three
      // quarters of the plot with an outline across all of it and a footer
      // reading 0 / 0.
      Shot(name: "window-one-request", size: windowSize) { await make(.one) },
      Shot(name: "window-two-requests", size: windowSize) { await make(.two) },
      Shot(name: "window-text-200k", size: windowSize) { await make(.small, withText: true) },
      // A session with many lanes, which is what turned the title bar into a
      // block 270 points tall and hid a broken window.
      Shot(name: "lanes", size: windowSize) { await manyLanes() },
      Shot(name: "window-replay-200k", size: windowSize) {
        let model = await make(.small)
        model.move(playheadTo: model.analysis.map { $0.lastRequest / 2 } ?? 0)
        return model
      },
      // Nothing focused, which is what the window shows until somebody types
      // /ctxscope or picks a session.
      Shot(name: "empty", size: windowSize) { await nothingFocused() },
    ]
  }

  /// The menu bar's popover, from synthetic sessions through the presenter,
  /// the way the app fills it: at both window sizes, at the two shortest
  /// lanes there are, and with nothing in focus.
  static var popovers: [Shot] {
    [
      Shot(name: "popover-200k", size: popoverSize) { await make(.small) },
      Shot(name: "popover-1m", size: popoverSize) { await make(.large) },
      Shot(name: "popover-one-request", size: popoverSize) { await make(.one) },
      Shot(name: "popover-two-requests", size: popoverSize) { await make(.two) },
      Shot(name: "popover-nothing-focused", size: popoverSize) { await nothingFocused() },
    ]
  }

  /// When a popover shot is taken: twelve seconds after the lane's last
  /// request, so the pictures do not change with the day they are made.
  static func popoverContext(_ model: InstrumentModel) -> PopoverPresenter.Context {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
    let written = model.analysis?.lane.snapshots.last?.timestamp ?? 0
    return PopoverPresenter.Context(
      now: Date(timeIntervalSince1970: written + 12), home: "/Users/someone", calendar: calendar)
  }

  enum Scale {
    case small
    case large
    case one
    case two

    var options: SyntheticRecording.Options {
      switch self {
      case .small: SyntheticRecording.Options()
      case .large: .millionTokenWindow
      case .one: .oneRequest
      case .two: .twoRequests
      }
    }
  }

  /// The window with no session focused. The sessions are there to be picked
  /// from; none of them is shown.
  static func nothingFocused() async -> InstrumentModel {
    let model = InstrumentModel(feed: RecordingFeed(recordings: [SyntheticRecording.make()]))
    model.reloadSessions()
    await model.settle()
    return model
  }

  /// One real session on this machine, for a private look at a window nobody
  /// could shape by hand.
  static func session(_ id: String) async -> InstrumentModel? {
    let feed = TranscriptFeed()
    guard let found = try? feed.sessions(reusing: [:]).first(where: { $0.id.hasPrefix(id) })
    else { return nil }
    let model = InstrumentModel(feed: feed)
    model.reloadSessions()
    model.focus(session: found.id)
    await model.settle()
    if let analysis = model.analysis,
      let top = analysis.topUnreferenced(at: model.playhead, count: 1).first
    {
      model.select(top.segment)
      await model.settle()
    }
    return model
  }

  /// One recording with a main lane and a dozen subagents, cut out of the
  /// synthetic one so no transcript is involved.
  static func manyLanes() async -> InstrumentModel {
    let recording = SyntheticRecording.make()
    guard let main = recording.mainLane else { return await make(.small) }
    let lanes =
      [main]
      + (1...12).map { index in
        Lane(
          id: LaneID("agent-\(index)"),
          agentType: ["general-purpose", "explore", "plan"][index % 3],
          window: main.window,
          segments: main.segments.filter { $0.born < 6 + index },
          snapshots: Array(main.snapshots.prefix(6 + index))
        )
      }
    let many = Recording(
      sessionID: recording.sessionID, project: recording.project,
      title: recording.title, lanes: lanes)
    let corpus = SyntheticJudge.corpus(for: main)
    let model = InstrumentModel(
      feed: RecordingFeed(
        recordings: [many],
        judgeInputs: [many.sessionID: [.main: corpus.input]]
      )
    )
    model.reloadSessions()
    await model.settle()
    model.focus(session: model.list.entries.first?.id)
    await model.settle()
    return model
  }

  /// A model over the synthetic recording, selected on the segment with the
  /// largest unreferenced cost so the sidebar and the strip have something to
  /// show.
  static func make(_ scale: Scale, withText: Bool = false) async -> InstrumentModel {
    let recording = SyntheticRecording.make(scale.options)
    let corpus = SyntheticJudge.corpus(
      for: recording.mainLane
        ?? Lane(
          id: .main, window: .given(1), segments: [], snapshots: []))
    let model = InstrumentModel(
      feed: RecordingFeed(
        recordings: [recording],
        judgeInputs: [recording.sessionID: [.main: corpus.input]],
        contents: withText ? [recording.sessionID: corpus.texts] : [:]
      )
    )
    model.reloadSessions()
    await model.settle()
    model.focus(session: model.list.entries.first?.id)
    await model.settle()
    guard let analysis = model.analysis else { return model }
    let live = analysis.carry.ranked.filter { cost in
      guard let segment = analysis.segment(cost.segment) else { return false }
      return cost.isAssessable && (cost.referencedShare ?? 0) > 0
        && segment.isLive(at: model.playhead)
        // A shot with text has to show a block's text, so the block it
        // selects has to be one the feed has text for.
        && (!withText || corpus.texts[cost.segment] != nil)
    }
    // With text, the most referenced segment. Otherwise the largest
    // unreferenced cost, which is what the table is ranked by.
    let pick =
      withText
      ? live.max { ($0.referencedShare ?? 0) < ($1.referencedShare ?? 0) } : live.first
    if let pick {
      model.select(pick.segment)
      // The text is loaded off the main actor, so a render that does not
      // wait for it shows an empty reader.
      await model.settle()
    }
    return model
  }
}

/// A page as `--page` names it: "context" or "timeline".
extension WindowPage {
  init?(argument: String) {
    guard let page = Self.allCases.first(where: { $0.argument == argument.lowercased() }) else {
      return nil
    }
    self = page
  }

  var argument: String { rawValue.lowercased() }
}
