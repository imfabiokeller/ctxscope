internal import Foundation
internal import ScopeCore

extension LaneBuilder {
  func collect(added: [String], index: Int, state: inout BuildState) -> Entering {
    var entering = Entering()
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
    // Owned by the turn's last entry so it leaves the context with it.
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

  struct Entering {
    static let noBlock = -1

    var pending: [PendingSegment] = []
    var pieces: [(uuid: String, block: Int, piece: ContentPiece)] = []
    var groupTotals: [Int: Int] = [:]
    var observedPrefixBands: Set<Band> = []

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
