internal import Foundation
internal import ScopeCapture
internal import ScopeCore

extension InstrumentModel {
  public func reloadSessions() {
    scan?.cancel()
    let feed = feed
    let known = Dictionary(
      list.entries.map { ($0.session.url.path, $0.session) },
      uniquingKeysWith: { first, _ in
        first
      })
    scan = Task { [weak self] in
      let found = await Task.detached(priority: .utility) {
        Result { try feed.sessions(reusing: known) }
      }.value
      guard let self else { return }
      // Cleared on every exit: a handle left by a cancelled task blocks every later load.
      defer { scan = nil }
      guard !Task.isCancelled else { return }
      switch found {
      case .success(let sessions):
        list.update(with: sessions)
        if let asked = pendingFocus {
          pendingFocus = nil
          if sessions.contains(where: { $0.id == asked }) { focus(session: asked) }
        }
        if list.focused != nil, list.wanted == nil { focus(session: nil) }
        failure = nil
      case .failure(let error):
        failure = "\(error)"
      }
      openWanted()
      // Only after the scan has answered: arming earlier watches an empty list.
      rearm()
    }
  }

  // A cancelled task whose model went away cannot clear its own handle, so it is cleared here.
  public func settle() async {
    while let pending = scan ?? work ?? text ?? lines {
      await pending.value
      if scan == pending { scan = nil }
      if work == pending { work = nil }
      if text == pending { text = nil }
      if lines == pending { lines = nil }
    }
  }

  func focus(afterScanFinds id: String) {
    pendingFocus = id
    reloadSessions()
  }

  public func focus(session id: String?) {
    // A choice made now beats an id a scan is still looking for.
    pendingFocus = nil
    guard id != list.focused else { return }
    list.focus(id)
    onFocusChanged?(id)
    guard id != nil else { return close() }
    openWanted()
  }

  func openWanted() {
    guard isOn else { return }
    guard list.focused != nil else { return close() }
    guard let wanted = list.wanted, wanted.id != opened?.id else { return }
    load(wanted)
  }

  func close() {
    work?.cancel()
    work = nil
    select(nil)
    liveness.clear()
    analysis = nil
    figures = nil
    promptLines = [:]
    blockNames = BlockNames()
    selectedPrompt = nil
    recording = nil
    opened = nil
    isLoading = false
    rearm()
  }

  private func load(_ session: SessionRef) {
    replay.stop()
    liveness.saw(activity: session.lastActivity)
    work?.cancel()
    // Segment ids are slot numbers, so an old selection would point at another block.
    select(nil)
    analysis = nil
    figures = nil
    promptLines = [:]
    blockNames = BlockNames()
    selectedPrompt = nil
    opened = session
    isLoading = true
    needsRefresh = false
    // Armed before the read finishes, or the first write after launch is missed.
    rearm()
    let host = host
    let hints = hints
    work = Task { [weak self] in
      let loaded = await attempt { try await host.load(session, hints: hints) }
      guard let self else { return }
      defer {
        work = nil
        isLoading = false
      }
      guard !Task.isCancelled else { return }
      adopt(loaded, keepingPlayhead: false)
    }
  }

  public func refresh() {
    guard opened != nil else { return }
    guard work == nil else {
      needsRefresh = true
      return
    }
    needsRefresh = false
    let host = host
    let lane = lane
    let hints = hints
    work = Task { [weak self] in
      let loaded = await attempt { try await host.refresh(lane: lane, hints: hints) }
      guard let self else { return }
      defer {
        work = nil
        if needsRefresh, !Task.isCancelled { refresh() }
      }
      guard !Task.isCancelled else { return }
      switch loaded {
      case .success(let value):
        guard let value else { return }
        adopt(.success(value), keepingPlayhead: true)
      case .failure(let error):
        failure = "\(error)"
      }
    }
  }

  func adopt(_ loaded: Result<SessionHost.Loaded, any Error>, keepingPlayhead: Bool) {
    switch loaded {
    case .failure(let error):
      analysis = nil
      figures = nil
      recording = nil
      failure = "\(error)"
    case .success(let value):
      failure = nil
      // Every lane counts: a subagent can work while the shown lane stands still.
      let requests = value.recording.lanes.reduce(0) { $0 + $1.snapshots.count }
      if seen?.session == value.recording.sessionID, requests > (seen?.requests ?? 0) {
        liveness.saw(activity: Date())
      }
      seen = (session: value.recording.sessionID, requests: requests)
      hints = value.hints
      recording = value.recording
      lane = value.lane
      analysis = value.analysis
      generation += 1
      list.update(
        lanes: value.recording, fill: value.analysis.tally(at: value.analysis.lastRequest)?.fill)
      if !keepingPlayhead || isAtLatest {
        playhead = value.analysis.lastRequest
        isAtLatest = true
      } else {
        playhead = min(playhead, value.analysis.lastRequest)
      }
      figures = value.analysis.figures(at: playhead)
      if let selection, value.analysis.segment(selection) == nil { select(nil) }
      loadTranscriptWords()
    }
  }
}
