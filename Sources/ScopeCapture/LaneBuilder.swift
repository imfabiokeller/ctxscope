internal import Foundation
internal import ScopeCore

/// Builds one lane out of one transcript file: requests in order, segments
/// entering and leaving, sizes assigned so every request total is exact.
struct LaneBuilder {
  /// Shingles kept per segment. A cap is what keeps a 1M-token window in
  /// memory, and a few hundred samples put the referenced share within a few
  /// percent.
  static let shingleCap = 400
  /// How far above its own estimate an entering block may be sized when a
  /// retirement freed the room it sits in.
  static let estimateTolerance = 1.5

  struct Output {
    var lane: Lane
    var judgeInput: JudgeInput
    /// The fit this lane accumulated, so fits can be pooled across sessions.
    var calibration: EstimatorCalibration
  }

  let id: LaneID
  let agentType: String?
  let parentToolUseID: String?
  let window: WindowEstimate?
  /// What other sessions of the same model were seen to hold, which raises the
  /// bound on a session that has not filled its own window yet.
  var windowHints: ModelWindowHints
  private var state: BuildState

  init(
    id: LaneID,
    agentType: String?,
    parentToolUseID: String?,
    window: WindowEstimate?,
    url: URL? = nil,
    windowHints: ModelWindowHints = ModelWindowHints()
  ) {
    self.id = id
    self.agentType = agentType
    self.parentToolUseID = parentToolUseID
    self.window = window
    self.windowHints = windowHints
    state = BuildState(url: url)
  }

  /// The text one segment was built from, read back out of the transcript.
  ///
  /// It is the text the judge shingled, so a file read comes back without the
  /// line numbers the harness printed in front of it: those are in the prompt,
  /// but no later output can quote them, so reuse is never measured against
  /// them. A tool block comes back as the definition the snapshot recorded,
  /// rendered as the JSON it is. Segments that stand for something the
  /// transcript never recorded, such as a band the prior invented, have no
  /// content and return nil.
  func content(of segment: SegmentID) -> SegmentContent? {
    let slot = segment.rawValue
    guard slot >= 0, slot < state.segments.count,
      let origin = state.owner[slot], !origin.uuid.isEmpty, origin.index >= 0,
      let entry = state.store.entry(origin.uuid)
    else { return nil }
    guard let text = text(of: entry, at: origin) else { return nil }
    return SegmentContent(
      segment: segment,
      band: state.segments[slot].band,
      label: state.segments[slot].label,
      text: text
    )
  }

  /// What each of these segments is about, read back out of the transcript,
  /// for the ones that say. A system block or a tool definition has none.
  func details(of segments: [SegmentID]) -> [SegmentID: BlockDetail] {
    var reading = DetailReader(store: state.store, reader: state.reader)
    var found: [SegmentID: BlockDetail] = [:]
    for segment in segments.sorted() {
      let slot = segment.rawValue
      guard slot >= 0, slot < state.segments.count, let origin = state.owner[slot],
        origin.kind == .block, !origin.uuid.isEmpty,
        let detail = reading.detail(entry: origin.uuid, piece: origin.index)
      else { continue }
      found[segment] = detail
    }
    return found
  }

  private func text(of entry: TranscriptEntry, at origin: BuildState.PieceOrigin) -> String? {
    switch origin.kind {
    case .tool:
      guard let attachment = entry.attachment else { return nil }
      return EntryReader.toolDefinition(attachment, at: origin.index)
    case .systemBlock:
      guard let attachment = entry.attachment else { return nil }
      let blocks = EntryReader.systemBlocks(attachment)
      guard origin.index < blocks.count else { return nil }
      return blocks[origin.index]
    case .block:
      let pieces = state.reader.pieces(of: entry)
      guard origin.index < pieces.count else { return nil }
      return pieces[origin.index].textForJudge
    }
  }

  /// Takes the lines that have arrived since the last call. Work is
  /// proportional to them, not to the session so far: every request already
  /// processed stays processed.
  mutating func append(_ entries: [TranscriptEntry], skippedLines: Int = 0) {
    for entry in entries { state.ingest(entry) }
    state.stats.skippedLines += skippedLines
    drain(final: false)
  }

  /// A builder for the same lane, holding what this one learned about the
  /// prefix and nothing else. Reading the file again through it gives the lane
  /// the evidence would have produced from the start.
  func restarted() -> LaneBuilder {
    var fresh = LaneBuilder(
      id: id, agentType: agentType, parentToolUseID: parentToolUseID, window: window,
      url: state.store.url, windowHints: windowHints)
    fresh.use(evidence: state.evidence)
    return fresh
  }

  /// Takes what a pass over the file found about the prefix. It has to be in
  /// hand before the first request is stepped, because that is where the
  /// prefix is derived.
  mutating func use(evidence: PrefixEvidence) {
    state.adopt(evidence)
  }

  /// What this lane found out about its prefix, so a capture that has to build
  /// it again does not look for it twice.
  var evidence: PrefixEvidence { state.evidence }

  /// True when prefix evidence arrived after the prefix had been derived, so
  /// this lane describes a prefix it now knows more about.
  var needsRestart: Bool { state.needsRestart }

  /// Lets go of what a finished read no longer needs. Anything asked for
  /// afterwards is read back from the file.
  mutating func settle() {
    state.store.settle()
  }

  /// Closes the lane. The last request is only processed here, because until
  /// the file ends more of its blocks can still arrive.
  mutating func finish() -> Output {
    drain(final: true)
    return output()
  }

  /// The lane as it stands, without closing the request in flight.
  func snapshotOutput() -> Output { output() }

  private mutating func drain(final: Bool) {
    let advance = state.advanceRequests(final: final)
    for index in advance.published {
      step(index: index, request: state.log.requests[index], state: &state)
    }
    for index in advance.grown {
      state.regrow(request: index)
    }
    state.settleRequests(final: final)
  }

  private func output() -> Output {
    var stats = state.stats
    stats.heldEntries = state.store.cachedCount
    let lane = Lane(
      id: id,
      agentType: agentType,
      parentToolUseID: parentToolUseID,
      window: window
        ?? WindowEstimate(
          observing: state.snapshots, state.compactionEvents, hints: windowHints),
      segments: state.segments,
      snapshots: state.snapshots,
      compactions: state.compactionEvents,
      events: state.events,
      prompts: state.prompts,
      calibration: state.sizer.rates,
      stats: stats,
      prefixSource: state.prefixSourceAtSplit ?? state.evidence.source,
      contextReport: state.evidence.report
    )
    return Output(
      lane: lane,
      judgeInput: JudgeInput(segments: state.judged, consumers: state.consumers),
      calibration: state.sizer.calibration
    )
  }

  private func step(index: Int, request: RequestGroup, state: inout BuildState) {
    let change = state.tracker.move(to: request.entry.parentUUID) {
      state.store.parent(of: $0)
    }
    // A compaction restarts the chain by design. Any other restart means the
    // history this request continued from is not in the file.
    if change.restarted, index > 0, state.log.compactions[index] == nil {
      state.stats.chainRestarts += 1
    }
    let parent = state.parentRequest(before: index)
    let expanded = state.expansion.expand(added: change.added) { state.live[$0] != nil }
    state.stats.toolCalls += expanded.toolCalls
    state.stats.toolCallsWithResult += expanded.toolCallsWithResult
    for (owner, results) in expanded.attached {
      state.attached[owner, default: []].append(contentsOf: results)
    }

    var leaving = 0
    // A result leaves when the call that produced it leaves.
    for uuid in change.removed.flatMap({ [$0] + (state.attached[$0] ?? []) }) {
      for slot in state.live[uuid] ?? [] where state.segments[slot].died == nil {
        state.segments[slot].died = index
        state.segments[slot].deathCause =
          state.log.compactions[index] == nil ? .chain : .compaction
        state.liveSlots.remove(slot)
        leaving += state.segments[slot].tokens.value
      }
      state.live.removeValue(forKey: uuid)
      state.attached.removeValue(forKey: uuid)
    }

    let entering = collect(added: expanded.added, index: index, state: &state)

    // Content can also leave with nothing in the transcript saying so. The
    // measured total is what gives it away.
    let retirement = Self.retire(
      overhang: state.sizer.carriedTokens - leaving - request.usage.promptTotal,
      enteringEstimate: entering.estimate(with: state.sizer.rates),
      at: index,
      segments: &state.segments,
      liveSlots: &state.liveSlots
    )
    if retirement.didRetire {
      leaving += retirement.tokens
      state.note(retirement, at: index)
    }

    let result = state.sizer.size(
      SizingRequest(
        measuredTotal: request.usage.promptTotal,
        entering: entering.pending,
        leavingTokens: leaving,
        groupTotals: entering.groupTotals,
        absorbSurplus: index == 0 || retirement.absorbsSurplus,
        // An entering block may come out half again as large as its own
        // estimate. Past that, the room came from the retirement's guess.
        estimateTolerance: retirement.didRetire ? Self.estimateTolerance : nil
      )
    )
    // The prefix at the first request is derived, not unattributed: it has a
    // name and a place. Everything later that nothing accounted for does not.
    if index > 0 { state.stats.unattributedTokens += result.unallocated }
    state.stats.rejectedMeasurements += result.rejectedGroups
    state.materialize(entering, sized: result.tokens, at: index, cap: Self.shingleCap)
    state.appendDerivedPrefix(
      result.unallocated,
      at: index,
      plan: state.evidence.plan(observed: entering.observedPrefixBands),
      source: state.evidence.source,
      // Room a retirement freed beyond what was needed is a guess that came
      // out generous, so it is estimated, not arithmetic.
      grade: retirement.absorbsSurplus ? .estimated : .derived
    )
    state.finish(
      request: request, index: index, parentRequest: parent, result: result)
  }
}
