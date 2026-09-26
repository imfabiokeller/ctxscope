internal import Foundation
internal import ScopeCore

/// Everything one lane build carries between requests. Kept apart from the
/// logic so the build loop reads as the sequence of decisions it is.
struct BuildState {
  var store: EntryStore
  var reader = EntryReader()
  var expansion = ChainExpansion()
  /// The API calls of this lane, assembled from the entries that carry them.
  var log = RequestLog()

  var sizer = SegmentSizer()
  var tracker = ChainTracker()
  var segments: [Segment] = []
  var judged: [JudgedSegment] = []
  var consumers: [JudgedConsumer] = []
  /// Entry uuid to the slots of the segments it produced.
  var live: [String: [Int]] = [:]
  /// Slot to the entry and content block that produced it, so a retirement can
  /// clean up without scanning every segment and a block's text can be found
  /// again without anything holding it.
  var owner: [Int: PieceOrigin] = [:]
  /// Slots currently in the context. Kept so retirement never has to walk the
  /// whole history to find the live set.
  var liveSlots: Set<Int> = []
  /// Slots the prior produced when the prefix was derived. A leftover while
  /// one of these is live is a leftover; a leftover with none of them live is
  /// a prefix being derived.
  var derivedPrefix: Set<Int> = []
  var attached: [String: [String]] = [:]
  /// Assistant entry uuid to the request it belongs to, so the request a new
  /// one continues from can be read off the chain.
  var requestOfEntry: [String: Int] = [:]
  var snapshots: [Snapshot] = []
  var compactionEvents: [CompactionEvent] = []
  var events: [LaneEvent] = []
  /// Blocks that are prompts the person typed, in the order they entered.
  var prompts: [SegmentID] = []
  var stats = CaptureStats()
  /// What the transcript records about the prefix, found by a pass over the
  /// file before it is read as a lane.
  var evidence = PrefixEvidence()
  /// Where the prefix split came from, recorded at the moment it happened, so
  /// nothing can claim a source that arrived afterwards.
  var prefixSourceAtSplit: PrefixSplit.Source?
  /// True when prefix evidence arrived after the prefix had been derived. The
  /// lane it describes is the one from the first request, so the capture is
  /// built again rather than patched.
  private(set) var needsRestart = false
  /// Requests met in file order. It is not the same as the number published,
  /// which depends on how much of the file has been handed over at once, and
  /// a `/context` run has to remember the same request however the file was
  /// read.
  private var requestsSeen = 0
  private var lastRequestKey = ""

  /// Takes evidence found before the file was read as a lane.
  mutating func adopt(_ found: PrefixEvidence) {
    guard prefixSourceAtSplit == nil else { return }
    evidence = found
  }

  /// Which entry, and which item of it, a segment came from.
  struct PieceOrigin: Sendable, Hashable {
    /// Which list of the entry `index` counts in. A snapshot's system prompt
    /// blocks and tool definitions are the prefix, so they are born at the
    /// first request while the record that holds them arrives later.
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

  /// Takes one line of the transcript. Nothing is decided here: entries are
  /// indexed and requests are collected until they are known to be finished.
  mutating func ingest(_ entry: TranscriptEntry) {
    store.keep(entry)
    reader.learn(from: entry)
    expansion.learn(from: entry)

    if entry.attachmentType == EntryReader.snapshotType
      || ContextUsage.isReport(entry)
    {
      if ContextUsage.isReport(entry) { stats.contextReports += 1 }
      // Evidence that turns up after the prefix was derived describes that
      // same prefix, so the lane has to be built again from the start.
      // The request it was run at is the last one before it in the file, which
      // is the one a person reading the report was looking at.
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

  /// Publishes every request that has started and brings the ones that grew up
  /// to date.
  mutating func advanceRequests(final: Bool) -> RequestLog.Advance {
    let advance = log.advance(final: final)
    for index in advance.published + advance.grown {
      for uuid in log.requests[index].uuids { requestOfEntry[uuid] = index }
    }
    return advance
  }

  /// Lets go of the requests that have been stepped through. Only here,
  /// because stepping one needs its blocks.
  mutating func settleRequests(final: Bool) {
    stats.unfinishedResponses += log.settle(final: final)
  }

  /// Takes the output side of a request again after more of it arrived. The
  /// segments it produced are not touched: they enter at the next request,
  /// which has not happened yet.
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

  /// Records an inferred retirement and drops the retired slots from the live
  /// map, which is why every slot remembers its owner.
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

  /// Gives the entering pieces their sizes and puts them into the context.
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
          // A tool definition is judged by whether its tool was called, the
          // same rule the prefix's tool blocks follow. Everything else is
          // judged by its words.
          isAssessable: pending.toolName != nil
            || BandRegistry.isAssessable(pending.band),
          // What the model produced points at the request that produced it.
          // Everything else came in from outside.
          isInput: pending.originRequest == nil,
          shingles: pending.toolName.map { [Shingler.toolCall($0)] }
            ?? (pending.contentClass == .image
              ? [] : Shingler.sampled(of: piece.piece.textForJudge, limit: cap))
        )
      )
    }
  }

  /// Closes one request: its snapshot, its consumer, and the events that the
  /// transcript recorded or the numbers imply.
  /// The request the chain currently ends in: what this one continues from.
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
