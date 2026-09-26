internal import Foundation
internal import ScopeCore

/// The part of the prefix no observed block accounts for: how it is divided,
/// and how it becomes blocks.
extension BuildState {
  /// The prefix at the first request, and any later leftover, are what the
  /// observed blocks could not account for.
  ///
  /// A part the harness counted, or whose text the transcript recorded, takes
  /// that size. The rest of the derived total goes to the bands nothing
  /// recorded, and if there are none it becomes one Unattributed block:
  /// spreading it over blocks that did not earn it would make every one of
  /// them wrong and would hide a number worth seeing.
  mutating func appendDerivedPrefix(
    _ tokens: Int,
    at index: Int,
    plan: PrefixSplit.Plan,
    source: PrefixSplit.Source,
    grade: Grade = .derived
  ) {
    guard tokens > 0 else { return }
    // With no derived prefix in the context, this is a prefix being derived,
    // not a leftover. The question is whether the split has already happened,
    // not whether anything prefix-shaped is live: a memory file or a skill
    // listing is a prefix band the transcript observed, and it is exactly what
    // shrinks the number being split here.
    guard derivedPrefix.isDisjoint(with: liveSlots) else {
      append(band: .unattr, label: "Unattributed", tokens: tokens, at: index, grade: grade)
      return
    }
    prefixSourceAtSplit = source
    let sized = plan.parts.map { $0.isShare ? nil : size(of: $0) }
    let total = sized.compactMap { $0 }.reduce(0, +)
    let shares = plan.parts.indices.filter { sized[$0] == nil }

    // More recorded than the request can hold: the sized parts keep their
    // proportions inside what there is, and nothing is left over. The request
    // total is the measured one and nothing may exceed it.
    // A share takes nothing here, not even the one token the allocator
    // gives every part it is handed: that token made a block for a band
    // nothing recorded, an MCP server that was never connected.
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

  /// What a part costs, when something said so: the harness's own count, or
  /// the estimator on the text the transcript recorded.
  private func size(of part: PrefixSplit.Part) -> Int {
    if let reported = part.reportedTokens { return reported }
    let estimate = sizer.rates.estimate(
      characters: part.characters, contentClass: part.contentClass)
    return max(1, Int(estimate.rounded()))
  }

  private mutating func append(_ part: PrefixSplit.Part, tokens: Int, at index: Int) {
    append(
      band: part.band, label: part.label, tokens: tokens, at: index,
      // A share of a derived total handed out by the prior is an estimate, and
      // so is a number the harness counted with its own tokenizer.
      grade: .estimated, part: part)
  }

  /// One block of the derived prefix.
  ///
  /// A block the transcript recorded remembers which item of which record it
  /// is, so its text can be read back out of the file and, for a tool, a call
  /// of it counts as a reference.
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
        // A tool definition can be judged now that it has a name: a schema
        // is referenced when its tool is called. A system
        // prompt block is a rule, which nothing has to quote to have followed.
        isAssessable: tool != nil,
        shingles: tool.map { [Shingler.toolCall($0.name)] } ?? []
      )
    )
  }
}
