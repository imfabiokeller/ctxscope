internal import Foundation
internal import ScopeCore

extension LaneBuilder {
  struct Retirement {
    var tokens = 0
    var count = 0
    var overshoot = 0
    var absorbsSurplus = false
    var hypothesis = ""

    var didRetire: Bool { tokens > 0 }
  }

  // Unexplained drops follow idle gaps, model switches or compactions, where all
  // live thinking went, so that set is tested first.
  static func retire(
    overhang: Int,
    enteringEstimate: Int,
    at index: Int,
    segments: inout [Segment],
    liveSlots: inout Set<Int>
  ) -> Retirement {
    guard overhang > 0 else { return Retirement() }

    var thinking: [Int] = []
    var thinkingTokens = 0
    for slot in liveSlots
    where segments[slot].band == .think && segments[slot].born < index {
      thinking.append(slot)
      thinkingTokens += segments[slot].tokens.value
    }

    let implied = thinkingTokens - overhang
    if !thinking.isEmpty, implied >= 0, fits(implied, enteringEstimate),
      !leavesTooMuchUnattributed(freed: thinkingTokens, implied: implied, enteringEstimate)
    {
      return apply(
        slots: thinking.sorted(),
        at: index,
        target: overhang,
        hypothesis: "all live thinking left",
        absorbsSurplus: true,
        countsOvershoot: false,
        segments: &segments,
        liveSlots: &liveSlots
      )
    }

    let candidates = liveSlots.filter { segments[$0].born < index }
    return apply(
      slots: bestFitting(
        candidates: candidates,
        floor: overhang,
        target: overhang + max(0, enteringEstimate),
        segments: segments
      ),
      at: index,
      target: overhang + max(0, enteringEstimate),
      hypothesis: "best fitting set of older content",
      absorbsSurplus: true,
      countsOvershoot: true,
      segments: &segments,
      liveSlots: &liveSlots
    )
  }

  private static func bestFitting(
    candidates: Set<Int>,
    floor: Int,
    target: Int,
    segments: [Segment]
  ) -> [Int] {
    let ordered = candidates.sorted { left, right in
      let leftRank = rank(segments[left])
      let rightRank = rank(segments[right])
      if leftRank != rightRank { return leftRank < rightRank }
      let leftTokens = segments[left].tokens.value
      let rightTokens = segments[right].tokens.value
      if leftTokens != rightTokens { return leftTokens > rightTokens }
      return segments[left].born < segments[right].born
    }
    var taken: [Int] = []
    var tokens = 0
    var rest: [Int] = []
    for slot in ordered {
      let size = segments[slot].tokens.value
      // The prefix is the least certain number: never spent to make room, only
      // reached below to cover the overhang.
      if rank(segments[slot]) < prefixRank, tokens + size <= target {
        taken.append(slot)
        tokens += size
      } else {
        rest.append(slot)
      }
    }
    while tokens < floor, !rest.isEmpty {
      let gap = floor - tokens
      let ordinary = rest.filter { rank(segments[$0]) < prefixRank }
      let pick = choose(from: ordinary.isEmpty ? rest : ordinary, gap: gap, segments: segments)
      guard let pick else { break }
      rest.removeAll { $0 == pick }
      taken.append(pick)
      tokens += segments[pick].tokens.value
    }
    return taken.sorted()
  }

  private static func choose(from slots: [Int], gap: Int, segments: [Segment]) -> Int? {
    let fitting = slots.filter { segments[$0].tokens.value >= gap }
    return fitting.min { segments[$0].tokens.value < segments[$1].tokens.value }
      ?? slots.max { segments[$0].tokens.value < segments[$1].tokens.value }
  }

  // A factor of three either way: accepts the right set, rejects a coincidence.
  private static func fits(_ implied: Int, _ estimate: Int) -> Bool {
    guard estimate > 0 else { return implied <= 64 }
    return implied <= estimate * 3 && implied * 3 >= estimate
  }

  // Past a third, the rest of the freed room had nowhere to go and the guess was wrong.
  static let unattributedLimit = 1.0 / 3

  private static func leavesTooMuchUnattributed(
    freed: Int,
    implied: Int,
    _ enteringEstimate: Int
  ) -> Bool {
    guard freed > 0 else { return false }
    let absorbable = Double(max(0, enteringEstimate))
    let unattributed = max(0, Double(implied) - absorbable)
    return unattributed > Double(freed) * unattributedLimit
  }

  private static let prefixRank = 2

  private static func rank(_ segment: Segment) -> Int {
    if segment.band == .think { return 0 }
    if BandRegistry.family(of: segment.band) == .prefix { return prefixRank }
    return 1
  }

  private static func apply(
    slots: [Int],
    at index: Int,
    target: Int,
    hypothesis: String,
    absorbsSurplus: Bool,
    countsOvershoot: Bool,
    segments: inout [Segment],
    liveSlots: inout Set<Int>
  ) -> Retirement {
    var result = Retirement(absorbsSurplus: absorbsSurplus, hypothesis: hypothesis)
    for slot in slots {
      segments[slot].died = index
      segments[slot].deathCause = .inferred
      liveSlots.remove(slot)
      result.tokens += segments[slot].tokens.value
      result.count += 1
    }
    result.overshoot = countsOvershoot ? max(0, result.tokens - target) : 0
    return result
  }

}
