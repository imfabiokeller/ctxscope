internal import CoreGraphics
public import Foundation
internal import ScopeCapture
public import ScopeCore

/// The state of the instrument window: which session and lane are shown, where
/// the playhead is, what is selected, and how it is colored.
@MainActor
@Observable
public final class InstrumentModel {
  public internal(set) var list = SessionList()
  public internal(set) var analysis: LaneAnalysis?
  public internal(set) var recording: Recording?
  /// Set when opening a session failed, so the window can say so instead of
  /// showing nothing.
  public internal(set) var failure: String?

  public internal(set) var lane: LaneID = .main
  public internal(set) var playhead = 0
  public internal(set) var selection: SegmentID?
  /// The figures at the playhead, worked out when it moves.
  public internal(set) var figures: PlayheadFigures?
  /// Which of the window's two pages is shown.
  public var page: WindowPage = .context
  /// The task the timeline shows, by its number, counted from one.
  public var selectedPrompt: Int?
  /// The first line of every typed prompt of the lane shown, read back from
  /// the transcript off the main actor. Empty until it arrives.
  public internal(set) var promptLines: [SegmentID: String] = [:]
  /// What every block of the lane shown is called, with what the transcript
  /// says it did, read back the same way. Labels alone until it arrives.
  public internal(set) var blockNames = BlockNames()
  /// Told when the focused session changes, so whoever owns the model can
  /// remember it across launches.
  @ObservationIgnored public var onFocusChanged: ((String?) -> Void)?
  /// True while the playhead is held at the newest request, which is what
  /// following a live session means.
  public internal(set) var isAtLatest = true

  public let replay = Replay()
  /// Whether the session being shown is being written to now. The menu bar
  /// item dims and drops its number unless this says otherwise.
  public let liveness: Liveness

  /// Whether ctxscope is on. False once `stop()` has been called and until
  /// `start()` is called again. A model that is off does nothing with what
  /// arrives: the item stays away, no transcript is read, and nothing is
  /// marked live.
  public private(set) var isOn = true
  /// True while a session is being opened or read. Opening a large session
  /// takes seconds, and a window that says nothing for seconds is a window
  /// that looks broken.
  public internal(set) var isLoading = false
  /// The selected block's text, loaded when the
  /// selection changes rather than while the body is being evaluated.
  public internal(set) var selectedText: SelectedText?

  let feed: any SessionFeed
  let watcher = SessionWatcher()
  let host: SessionHost
  var opened: SessionRef?
  var hints = ModelWindowHints()
  /// The work in flight, so a second request cancels the first rather than
  /// racing it.
  @ObservationIgnored var work: Task<Void, Never>?
  @ObservationIgnored var scan: Task<Void, Never>?
  @ObservationIgnored var text: Task<Void, Never>?
  @ObservationIgnored var lines: Task<Void, Never>?
  /// The Timeline page's data, kept until the lane, the selected prompt or
  /// the prompt lines change: its chart walks every block of every request.
  @ObservationIgnored var timeline: (key: TimelineKey, data: TimelineData)?
  /// Counts the analyses adopted, so a lane read again is a new key.
  @ObservationIgnored var generation = 0
  /// Set when something arrived while a read was already running. The last
  /// burst of a turn lands during the previous refresh, and dropping it left
  /// the fill stale until the next prompt: a lag of one request.
  @ObservationIgnored var needsRefresh = false
  /// An id a `show` URL named that the list did not have. The next scan either
  /// finds it, and it becomes the focus, or it is let go and whatever is
  /// focused now stays.
  @ObservationIgnored var pendingFocus: String?
  /// How many requests this session had the last time it was read, across
  /// every lane. What grows since is what says the session is working now.
  @ObservationIgnored var seen: (session: String, requests: Int)?
  public init(feed: any SessionFeed, clock: any WaitClock = RealClock()) {
    self.feed = feed
    liveness = Liveness(clock: clock)
    host = SessionHost(feed: feed)
    replay.onStep = { [weak self] in self?.stepReplay() }
    watcher.onChange = { [weak self] in self?.somethingChanged() }
    watcher.onVanished = { [weak self] in self?.somethingVanished() }
  }

  // MARK: following

  /// Reads the sessions and starts following whatever is written from now on.
  /// The watch is armed by the scan, which is the first moment there is a file
  /// to watch.
  public func start() {
    isOn = true
    reloadSessions()
  }

  /// Stops following. Everything in flight is cancelled and forgotten, so a
  /// later `start()` opens the session again rather than waiting on a task
  /// that will never answer. Closing the window inside the seconds a large
  /// session takes to open used to leave the model loading forever.
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

  // MARK: lanes, playhead, selection

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

  /// Moves the selection through the blocks alive at the playhead, in the
  /// order the model reads them.
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
    // Loaded here, not while the body is evaluated: it reads the transcript.
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

  // MARK: replay

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

/// `Result` has no async initializer, and a do/catch at every call site would
/// bury what the call sites are doing.
func attempt<Value>(
  _ body: sending () async throws -> Value
) async -> Result<Value, any Error> {
  do {
    return .success(try await body())
  } catch {
    return .failure(error)
  }
}
