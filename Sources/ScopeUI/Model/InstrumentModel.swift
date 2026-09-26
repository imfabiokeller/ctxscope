internal import CoreGraphics
public import Foundation
internal import ScopeCapture
public import ScopeCore

@MainActor
@Observable
public final class InstrumentModel {
  public internal(set) var list = SessionList()
  public internal(set) var analysis: LaneAnalysis?
  public internal(set) var recording: Recording?
  public internal(set) var failure: String?

  public internal(set) var lane: LaneID = .main
  public internal(set) var playhead = 0
  public internal(set) var selection: SegmentID?
  public internal(set) var figures: PlayheadFigures?
  public var page: WindowPage = .context
  public var selectedPrompt: Int?
  public internal(set) var promptLines: [SegmentID: String] = [:]
  public internal(set) var blockNames = BlockNames()
  @ObservationIgnored public var onFocusChanged: ((String?) -> Void)?
  public internal(set) var isAtLatest = true

  public let replay = Replay()
  public let liveness: Liveness

  public private(set) var isOn = true
  public internal(set) var isLoading = false
  public internal(set) var selectedText: SelectedText?

  let feed: any SessionFeed
  let watcher = SessionWatcher()
  let host: SessionHost
  var opened: SessionRef?
  var hints = ModelWindowHints()
  @ObservationIgnored var work: Task<Void, Never>?
  @ObservationIgnored var scan: Task<Void, Never>?
  @ObservationIgnored var text: Task<Void, Never>?
  @ObservationIgnored var lines: Task<Void, Never>?
  @ObservationIgnored var timeline: (key: TimelineKey, data: TimelineData)?
  @ObservationIgnored var generation = 0
  @ObservationIgnored var needsRefresh = false
  @ObservationIgnored var pendingFocus: String?
  @ObservationIgnored var seen: (session: String, requests: Int)?
  public init(feed: any SessionFeed, clock: any WaitClock = RealClock()) {
    self.feed = feed
    liveness = Liveness(clock: clock)
    host = SessionHost(feed: feed)
    replay.onStep = { [weak self] in self?.stepReplay() }
    watcher.onChange = { [weak self] in self?.somethingChanged() }
    watcher.onVanished = { [weak self] in self?.somethingVanished() }
  }

  public func start() {
    isOn = true
    reloadSessions()
  }

  public func stop() {
    isOn = false
    watcher.stop()
    replay.stop()
    work?.cancel()
    scan?.cancel()
    text?.cancel()
    lines?.cancel()
    work = nil
    scan = nil
    text = nil
    lines = nil
    isLoading = false
    opened = nil
    liveness.clear()
  }

  public func show(lane id: LaneID) {
    guard lane != id, recording?.lane(id) != nil else { return }
    lane = id
    select(nil)
    selectedPrompt = nil
    isLoading = true
    let host = host
    let hints = hints
    work?.cancel()
    work = Task { [weak self] in
      let loaded = await attempt { try await host.show(lane: id, hints: hints) }
      guard let self else { return }
      defer {
        work = nil
        isLoading = false
      }
      guard !Task.isCancelled else { return }
      switch loaded {
      case .success(let value):
        guard let value else { return }
        adopt(.success(value), keepingPlayhead: false)
      case .failure(let error):
        failure = "\(error)"
      }
    }
  }

  public func move(playheadTo request: Int) {
    guard let analysis else { return }
    let wanted = max(0, min(request, analysis.lastRequest))
    guard wanted != playhead else { return }
    playhead = wanted
    isAtLatest = playhead == analysis.lastRequest
    figures = analysis.figures(at: playhead)
  }

  public func moveSelection(by offset: Int) {
    let live = figures?.column.slices.map(\.segment) ?? []
    guard !live.isEmpty else { return }
    guard let current = selection, let slot = live.firstIndex(of: current) else {
      return select(live[offset < 0 ? live.count - 1 : 0])
    }
    select(live[max(0, min(live.count - 1, slot + offset))])
  }

  public func select(_ segment: SegmentID?) {
    selection = segment
    guard let segment, let analysis, let found = analysis.segment(segment) else {
      selectedText = nil
      return
    }
    selectedText = SelectedText(segment: found.id, text: nil)
    let host = host
    let lane = lane
    text?.cancel()
    text = Task { [weak self] in
      let found = await host.text(of: segment, lane: lane)
      guard let self else { return }
      defer { text = nil }
      guard !Task.isCancelled, selection == segment else { return }
      selectedText = SelectedText(segment: segment, text: found)
    }
  }

  private func stepReplay() {
    guard let analysis else { return replay.stop() }
    guard playhead < analysis.lastRequest else { return replay.stop() }
    move(playheadTo: playhead + 1)
  }

  public func toggleReplay() {
    guard let analysis else { return }
    if replay.isRunning {
      replay.stop()
    } else {
      if playhead >= analysis.lastRequest { move(playheadTo: 0) }
      replay.start(requests: analysis.requestCount)
    }
  }
}

func attempt<Value>(
  _ body: sending () async throws -> Value
) async -> Result<Value, any Error> {
  do {
    return .success(try await body())
  } catch {
    return .failure(error)
  }
}
