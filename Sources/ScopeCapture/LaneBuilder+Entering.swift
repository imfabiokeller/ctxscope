internal import Foundation
internal import ScopeCore

/// What entered at one request, and how it is collected.
///
/// Separate from the building of a lane because it is one job: turning the
/// entries a request added into pending segments in prompt order, with the
/// framing the harness never wrote down.
extension LaneBuilder {
  /// Turns the entries that entered into pending segments, in prompt order.
  func collect(added: [String], index: Int, state: inout BuildState) -> Entering {
    var entering = Entering()
    // A response is only sized from its measured output when all of its
    // streamed entries entered together. A half-added response falls back to
    // the estimator.
    var addedPerRequest: [String: Int] = [:]
    for uuid in added {
      guard let entry = state.store.entry(uuid), entry.kind == "assistant" else { continue }
      addedPerRequest[entry.requestID ?? uuid, default: 0] += 1
    }
    for uuid in added {
      guard let entry = state.store.entry(uuid) else { continue }
      let pieces = state.reader.pieces(of: entry)
      guard !pieces.isEmpty else { continue }
      let key = entry.requestID ?? uuid
      let origin = state.log.byKey[key]
      let groups = Self.groups(
        for: entry,
        pieces: pieces,
        origin: origin,
        originIndex: state.log.indexByKey[key],
        complete: addedPerRequest[key] == (origin?.entryCount ?? 0),
        totals: &entering.groupTotals
      )
      for (slot, piece) in pieces.enumerated() {
        entering.pending.append(
          PendingSegment(
            band: piece.band,
            label: piece.label,
            characters: piece.characters,
            contentClass: piece.contentClass,
            contentHash: Shingler.hash(piece.text),
            group: groups[slot],
            originRequest: piece.role == .input ? nil : state.log.indexByKey[key],
            isReliable: piece.isReliable,
            toolName: piece.toolName
          )
        )
        entering.pieces.append((uuid, slot, piece))
        if BandRegistry.family(of: piece.band) == .prefix, piece.characters > 0 {
          entering.observedPrefixBands.insert(piece.band)
        }
      }
    }
    // What the harness injected around this turn and never wrote down. It
    // belongs to the turn, not to whichever block happened to arrive with it.
    //
    // It is owned by the last entry of the turn, so it leaves the context when
    // that entry does. Owned by nothing, it never died with its chain, and
    // both compactions of one real session then swept 43k and 68k tokens of
    // framing as inferred retirements and left ghosts behind after a rewind.
    if entering.pending.contains(where: { $0.group == nil }), let owner = entering.pieces.last {
      entering.pending.append(
        PendingSegment(
          band: .user,
          label: "Harness framing",
          characters: 0,
          contentClass: .prose,
          contentHash: Shingler.hash("framing-\(index)"),
          framingAllowance: state.sizer.framingEstimate
        )
      )
      entering.pieces.append(
        (uuid: owner.uuid, block: Entering.noBlock, piece: ContentPiece.framing))
    }
    return entering
  }

  /// What entered at one request, before it has a size.
  struct Entering {
    /// A segment that stands for something the transcript never recorded, so
    /// there is no content block behind it to read back.
    static let noBlock = -1

    var pending: [PendingSegment] = []
    var pieces: [(uuid: String, block: Int, piece: ContentPiece)] = []
    var groupTotals: [Int: Int] = [:]
    /// Prefix bands the transcript recorded the content of at this request.
    /// The prior never splits a band that is already there with its own text.
    var observedPrefixBands: Set<Band> = []

    /// What the estimator expects this to cost. The retirement hypothesis is
    /// tested against it.
    func estimate(with rates: EstimatorRates) -> Int {
      var total = groupTotals.values.reduce(0, +)
      for segment in pending where segment.group == nil || groupTotals[segment.group!] == nil {
        total += Int(
          rates.estimate(characters: segment.characters, contentClass: segment.contentClass))
      }
      return total
    }
  }
}
