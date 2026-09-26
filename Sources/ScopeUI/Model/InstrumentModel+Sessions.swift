internal import Foundation
internal import ScopeCapture
internal import ScopeCore

/// Finding sessions and opening them. Everything here happens off the main
/// actor and comes back as a value, because a scan of this machine takes most
/// of a second and opening a large session takes seconds.
extension InstrumentModel {
  /// Re-reads the session list, off the main actor, and opens whichever
  /// session should be shown.
  ///
  /// A scan of this machine's 193 sessions took 0.78 s when every tail was
  /// read for its title. It is now a directory listing plus the tails of the
  /// files that changed, and it does not happen on the main thread either way.
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
      // The handle goes on every exit, cancelled or not. A handle left behind
      // by a cancelled task is what made the window refuse to load again.
      defer { scan = nil }
      guard !Task.isCancelled else { return }
      switch found {
      case .success(let sessions):
        list.update(with: sessions)
        // An id somebody asked for that the list did not have. It becomes the
        // focus now if this scan found it, and is dropped if it did not.
        if let asked = pendingFocus {
          pendingFocus = nil
          if sessions.contains(where: { $0.id == asked }) { focus(session: asked) }
        }
        // A focused session this machine no longer has is not focused any
        // more, and the window says so rather than showing the last one.
        if list.focused != nil, list.wanted == nil { focus(session: nil) }
        failure = nil
      case .failure(let error):
        failure = "\(error)"
      }
      openWanted()
      // The list is only known once the scan has answered, so this is the
      // first moment there is anything to watch. Arming before it watched an
      // empty list, which is a watcher that never fires.
      rearm()
    }
  }

  /// Waits for whatever is in flight, for a caller that needs the answer
  /// before it can do anything: the snapshot renderer, the bench, a test.
  ///
  /// A task that finished but could not clear its own handle, which is what a
  /// cancelled task whose model went away looks like, is cleared here. Without
  /// that this loop spins on a handle nobody will ever take back.
  public func settle() async {
    while let pending = scan ?? work ?? text ?? lines {
      await pending.value
      if scan == pending { scan = nil }
      if work == pending { work = nil }
      if text == pending { text = nil }
      if lines == pending { lines = nil }
    }
  }

  /// Focuses a session the list does not have yet, if a scan finds it. What is
  /// focused now stays focused until then, and stays for good if the scan
  /// comes back without it.
  func focus(afterScanFinds id: String) {
    pendingFocus = id
    reloadSessions()
  }

  /// Shows this session and only this session. The one that was shown before
  /// simply stops being shown: nothing else happens to it.
  public func focus(session id: String?) {
    // A choice made now beats an id a scan is still looking for. Without
    // this, a scan that took a third of a second landed afterwards and moved
    // the focus to whatever the URL before it had named.
    pendingFocus = nil
    guard id != list.focused else { return }
    list.focus(id)
    onFocusChanged?(id)
    guard id != nil else { return close() }
    openWanted()
  }

  func openWanted() {
    // A model that is off reads nothing. The focus is kept, and `start()`
    // opens it, so whoever turns ctxscope on and focuses a session may do the
    // two in either order.
    guard isOn else { return }
    guard list.focused != nil else { return close() }
    // Focused but not in the list yet is what a session that has only just
    // been written looks like. The next scan finds it.
    guard let wanted = list.wanted, wanted.id != opened?.id else { return }
    load(wanted)
  }

  /// Nothing is focused, or what was focused is not on this machine any more.
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
    // A session is live from when it was last written to, which the file
    // itself says. Opening one that has been idle all morning does not make
    // it live, and opening one written a second ago does.
    liveness.saw(activity: session.lastActivity)
    work?.cancel()
    // Segment ids are slot numbers, so the id of the old session's selection
    // usually exists in the new one and points at something else entirely.
    // Nothing selected in a session that is being replaced survives it.
    select(nil)
    analysis = nil
    figures = nil
    promptLines = [:]
    blockNames = BlockNames()
    selectedPrompt = nil
    opened = session
    isLoading = true
    needsRefresh = false
    // Watched from the moment it is opened, so the first line written after a
    // launch is read. Waiting for the read to finish would miss it.
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

  /// Reads whatever the open session has gained. Driven by file system events,
  /// so nothing here runs while nothing is happening.
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
        // Whatever arrived while this was running is read now rather than
        // waiting for the next thing to happen.
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
      // Requests that were not there before are a write that just happened,
      // whatever the last scan of the directory said. Every lane counts: a
      // subagent working for five minutes is the session working, and the
      // lane being shown can stand still for all of it.
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
