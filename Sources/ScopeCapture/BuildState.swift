internal import Foundation
internal import ScopeCore

struct BuildState {
  var store: EntryStore
  var reader = EntryReader()
  var expansion = ChainExpansion()
  var log = RequestLog()

  var sizer = SegmentSizer()
  var tracker = ChainTracker()
  var segments: [Segment] = []
  var judged: [JudgedSegment] = []
  var consumers: [JudgedConsumer] = []
  var live: [String: [Int]] = [:]
  var owner: [Int: PieceOrigin] = [:]
  var liveSlots: Set<Int> = []
  var derivedPrefix: Set<Int> = []
  var attached: [String: [String]] = [:]
  var requestOfEntry: [String: Int] = [:]
  var snapshots: [Snapshot] = []
  var compactionEvents: [CompactionEvent] = []
  var events: [LaneEvent] = []
  var prompts: [SegmentID] = []
  var stats = CaptureStats()
  var evidence = PrefixEvidence()
  var prefixSourceAtSplit: PrefixSplit.Source?
  private(set) var needsRestart = false
  // Counted in file order, not published order, so a `/context` report maps to
  // the same request however much of the file was read at once.
  private var requestsSeen = 0
  private var lastRequestKey = ""

  mutating func adopt(_ found: PrefixEvidence) {
    guard prefixSourceAtSplit == nil else { return }
    evidence = found
  }

  struct PieceOrigin: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
      case block
      case systemBlock
      case tool
    }

    var uuid: String
    var index: Int
    var kind: Kind = .block
  }

  init(url: URL? = nil) {
    store = EntryStore(url: url)
  }

  mutating func ingest(_ entry: TranscriptEntry) {
    store.keep(entry)
    reader.learn(from: entry)
    expansion.learn(from: entry)

    if entry.attachmentType == EntryReader.snapshotType
      || ContextUsage.isReport(entry)
    {
      if ContextUsage.isReport(entry) { stats.contextReports += 1 }
      // A report belongs to the last request before it in the file.
      let at = max(0, requestsSeen - 1)
      if evidence.learn(from: entry, at: at), prefixSourceAtSplit != nil { needsRestart = true }
      return
    }
    if entry.kind == "system", entry.systemSubtype == "compact_boundary",
      let metadata = entry.compactMetadata
    {
      log.note(compaction: metadata)
      return
    }
    guard entry.kind == "assistant", entry.usage != nil else { return }
    let key = entry.requestID ?? entry.uuid ?? ""
    if key != lastRequestKey {
      lastRequestKey = key
      requestsSeen += 1
    }
    log.ingest(entry)
  }

  mutating func advanceRequests(final: Bool) -> RequestLog.Advance {
    let advance = log.advance(final: final)
    for index in advance.published + advance.grown {
      for uuid in log.requests[index].uuids { requestOfEntry[uuid] = index }
    }
    return advance
  }

  mutating func settleRequests(final: Bool) {
    stats.unfinishedResponses += log.settle(final: final)
  }

  mutating func regrow(request index: Int) {
    let request = log.requests[index]
    consumers[index] = JudgedConsumer(
      request: index, shingles: LaneBuilder.consumerShingles(request: request))
    let previous = snapshots[index]
    snapshots[index] = Snapshot(
      index: previous.index,
      requestID: previous.requestID,
      timestamp: previous.timestamp,
      model: previous.model,
      usage: request.usage,
      parentRequest: previous.parentRequest,
      residualTokens: previous.residualTokens,
      appendedTokens: previous.appendedTokens
    )
  }

  mutating func note(_ retirement: LaneBuilder.Retirement, at index: Int) {
    stats.inferredRetirements += retirement.count
    stats.inferredRetirementTokens += retirement.tokens
    stats.inferredRetirementOvershoot += retirement.overshoot
    for slot in segments.indices
    where segments[slot].died == index
      && segments[slot].deathCause == .inferred
    {
      guard let origin = owner[slot], var slots = live[origin.uuid] else { continue }
      slots.removeAll { $0 == slot }
      if slots.isEmpty {
        live.removeValue(forKey: origin.uuid)
      } else {
        live[origin.uuid] = slots
      }
    }
    events.append(
      LaneEvent(
        request: index,
        kind: .inferredRetirement,
        tokens: Tokens(retirement.tokens, .estimated),
        detail: "\(retirement.count) segments, hypothesis: \(retirement.hypothesis)"
          + (retirement.overshoot > 0
            ? ", overshoot \(TokenFormat.tokens(retirement.overshoot)) tokens" : "")
      )
    )
  }

  mutating func materialize(
    _ entering: LaneBuilder.Entering,
    sized: [Tokens],
    at index: Int,
    cap: Int
  ) {
    for (slot, tokens) in sized.enumerated() {
      let piece = entering.pieces[slot]
      let pending = entering.pending[slot]
      let id = SegmentID(segments.count)
      segments.append(
        Segment(
          id: id,
          band: pending.band,
          label: pending.label,
          tokens: tokens,
          characters: pending.characters,
          contentClass: pending.contentClass,
          born: index,
          contentHash: pending.contentHash,
          originRequest: pending.originRequest
        )
      )
      let created = segments.count - 1
      live[piece.uuid, default: []].append(created)
      owner[created] = PieceOrigin(uuid: piece.uuid, index: piece.block)
      liveSlots.insert(created)
      if piece.piece.isPrompt { prompts.append(id) }
      store.release(piece.uuid)
      judged.append(
        JudgedSegment(
          id: id,
          born: index,
          isAssessable: pending.toolName != nil
            || BandRegistry.isAssessable(pending.band),
          isInput: pending.originRequest == nil,
          shingles: pending.toolName.map { [Shingler.toolCall($0)] }
            ?? (pending.contentClass == .image
              ? [] : Shingler.sampled(of: piece.piece.textForJudge, limit: cap))
        )
      )
    }
  }

  func parentRequest(before index: Int) -> Int? {
    for uuid in tracker.chain.reversed() {
      if let found = requestOfEntry[uuid], found < index { return found }
    }
    return nil
  }

  mutating func finish(
    request: LaneBuilder.RequestGroup,
    index: Int,
    parentRequest: Int?,
    result: SizingResult
  ) {
    let model = request.entry.model ?? "unknown"
    if let previous = snapshots.last, previous.model != model {
      events.append(
        LaneEvent(
          request: index,
          kind: .modelSwitch,
          tokens: Tokens(request.usage.promptTotal, .measured),
          detail: "\(previous.model) to \(model)"
        )
      )
    }
    consumers.append(
      JudgedConsumer(request: index, shingles: LaneBuilder.consumerShingles(request: request))
    )
    snapshots.append(
      Snapshot(
        index: index,
        requestID: request.entry.requestID,
        timestamp: request.entry.timestamp ?? 0,
        model: model,
        usage: request.usage,
        parentRequest: parentRequest,
        residualTokens: result.residualTokens,
        appendedTokens: result.appendedTokens
      )
    )
    guard let boundary = log.compactions[index] else { return }
    compactionEvents.append(
      CompactionEvent(
        atRequest: index,
        trigger: boundary["trigger"]?.string ?? "unknown",
        preTokens: boundary["preTokens"]?.int ?? 0,
        postTokens: boundary["postTokens"]?.int ?? 0,
        droppedTokens: boundary["cumulativeDroppedTokens"]?.int ?? 0
      )
    )
    events.append(
      LaneEvent(
        request: index,
        kind: .compaction,
        tokens: Tokens(
          max(0, (boundary["preTokens"]?.int ?? 0) - (boundary["postTokens"]?.int ?? 0)),
          .measured),
        detail: "trigger \(boundary["trigger"]?.string ?? "unknown")"
      )
    )
  }
}
