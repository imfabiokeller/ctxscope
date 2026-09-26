internal import Foundation
internal import ScopeCore

struct LaneBuilder {
  // Caps memory on a 1M-token window; a few hundred samples keep the reused
  // share within a few percent.
  static let shingleCap = 400
  static let estimateTolerance = 1.5

  struct Output {
    var lane: Lane
    var judgeInput: JudgeInput
    var calibration: EstimatorCalibration
  }

  let id: LaneID
  let agentType: String?
  let parentToolUseID: String?
  let window: WindowEstimate?
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

  mutating func append(_ entries: [TranscriptEntry], skippedLines: Int = 0) {
    for entry in entries { state.ingest(entry) }
    state.stats.skippedLines += skippedLines
    drain(final: false)
  }

  func restarted() -> LaneBuilder {
    var fresh = LaneBuilder(
      id: id, agentType: agentType, parentToolUseID: parentToolUseID, window: window,
      url: state.store.url, windowHints: windowHints)
    fresh.use(evidence: state.evidence)
    return fresh
  }

  mutating func use(evidence: PrefixEvidence) {
    state.adopt(evidence)
  }

  var evidence: PrefixEvidence { state.evidence }

  var needsRestart: Bool { state.needsRestart }

  mutating func settle() {
    state.store.settle()
  }

  mutating func finish() -> Output {
    drain(final: true)
    return output()
  }

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
        estimateTolerance: retirement.didRetire ? Self.estimateTolerance : nil
      )
    )
    // The first request's leftover is the derived prefix, not unattributed.
    if index > 0 { state.stats.unattributedTokens += result.unallocated }
    state.stats.rejectedMeasurements += result.rejectedGroups
    state.materialize(entering, sized: result.tokens, at: index, cap: Self.shingleCap)
    state.appendDerivedPrefix(
      result.unallocated,
      at: index,
      plan: state.evidence.plan(observed: entering.observedPrefixBands),
      source: state.evidence.source,
      grade: retirement.absorbsSurplus ? .estimated : .derived
    )
    state.finish(
      request: request, index: index, parentRequest: parent, result: result)
  }
}
