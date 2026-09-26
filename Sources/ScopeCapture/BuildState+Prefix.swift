internal import Foundation
internal import ScopeCore

extension BuildState {
  mutating func appendDerivedPrefix(
    _ tokens: Int,
    at index: Int,
    plan: PrefixSplit.Plan,
    source: PrefixSplit.Source,
    grade: Grade = .derived
  ) {
    guard tokens > 0 else { return }
    // Only the derived slots count: observed prefix bands (a memory file, a skill
    // listing) are live too and are what shrinks the number split here.
    guard derivedPrefix.isDisjoint(with: liveSlots) else {
      append(band: .unattr, label: "Unattributed", tokens: tokens, at: index, grade: grade)
      return
    }
    prefixSourceAtSplit = source
    let sized = plan.parts.map { $0.isShare ? nil : size(of: $0) }
    let total = sized.compactMap { $0 }.reduce(0, +)
    let shares = plan.parts.indices.filter { sized[$0] == nil }

    // Shares get nothing here: the allocator's one-token minimum would make a
    // block for a band nothing recorded.
    guard total < tokens else {
      let recorded = plan.parts.indices.filter { sized[$0] != nil }
      let scaled = Normalizer.allocate(
        total: tokens, weights: recorded.map { Double(sized[$0] ?? 0) })
      for (position, value) in zip(recorded, scaled) where value > 0 {
        append(plan.parts[position], tokens: value, at: index)
      }
      return
    }
    for (part, value) in zip(plan.parts, sized) where (value ?? 0) > 0 {
      append(part, tokens: value ?? 0, at: index)
    }
    let rest = tokens - total
    guard rest > 0 else { return }
    guard !shares.isEmpty else {
      stats.unattributedTokens += rest
      append(band: .unattr, label: "Unattributed", tokens: rest, at: index, grade: .estimated)
      return
    }
    let parts = shares.map { plan.parts[$0] }
    let values = Normalizer.allocate(total: rest, weights: parts.map(\.weight))
    for (part, value) in zip(parts, values) where value > 0 {
      append(part, tokens: value, at: index)
    }
  }

  private func size(of part: PrefixSplit.Part) -> Int {
    if let reported = part.reportedTokens { return reported }
    let estimate = sizer.rates.estimate(
      characters: part.characters, contentClass: part.contentClass)
    return max(1, Int(estimate.rounded()))
  }

  private mutating func append(_ part: PrefixSplit.Part, tokens: Int, at index: Int) {
    append(
      band: part.band, label: part.label, tokens: tokens, at: index,
      // Estimated even for a harness count, which uses its own tokenizer.
      grade: .estimated, part: part)
  }

  private mutating func append(
    band: Band,
    label: String,
    tokens: Int,
    at index: Int,
    grade: Grade,
    part: PrefixSplit.Part? = nil
  ) {
    let id = SegmentID(segments.count)
    segments.append(
      Segment(
        id: id,
        band: band,
        label: label,
        tokens: Tokens(tokens, grade),
        characters: part?.characters ?? 0,
        contentClass: part?.contentClass ?? .prose,
        born: index,
        contentHash: Shingler.hash("derived-\(label)-\(index)"),
        originRequest: nil
      )
    )
    let slot = segments.count - 1
    liveSlots.insert(slot)
    derivedPrefix.insert(slot)
    var tool: ContextReport.Tool?
    switch part?.item {
    case .systemBlock(let position):
      if let uuid = evidence.systemEntry {
        owner[slot] = PieceOrigin(uuid: uuid, index: position, kind: .systemBlock)
      }
    case .tool(let found):
      tool = found
      if let uuid = evidence.toolsEntry {
        owner[slot] = PieceOrigin(uuid: uuid, index: found.index, kind: .tool)
      }
    case nil:
      break
    }
    judged.append(
      JudgedSegment(
        id: id,
        born: index,
        isAssessable: tool != nil,
        shingles: tool.map { [Shingler.toolCall($0.name)] } ?? []
      )
    )
  }
}
