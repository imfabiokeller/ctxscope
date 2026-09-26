internal import Foundation
internal import ScopeCore

extension LaneBuilder {
  /// The result of deciding what left the context without the transcript
  /// saying so.
  struct Retirement {
    var tokens = 0
    var count = 0
    /// Tokens taken beyond the room the overhang and the entering content
    /// asked for. A retirement can only stop on a segment boundary, so it
    /// overshoots; the set hypothesis does not overshoot, it retires a set
    /// that means something.
    var overshoot = 0
    /// True when the room this freed must not be handed to the entering
    /// segments. It was freed by a guess about which segments left, so any
    /// surplus is that guess being wrong, not those segments being large.
    /// Both paths are guesses, so both set it.
    var absorbsSurplus = false
    var hypothesis = ""

    var didRetire: Bool { tokens > 0 }
  }

  /// Decides what left the context when the measured total is smaller than the
  /// reconstruction.
  ///
  /// What actually happens on this machine: the context shrinks with nothing
  /// in the transcript to explain it at ten points across seven sessions, and
  /// every one of them is a long idle gap (9195 s to 48739 s, cache cold), a
  /// model switch, or a compaction. It is not a per-turn stripping of
  /// thinking: one of those sessions has 59 user prompts and one drop.
  ///
  /// So the first hypothesis tested is the one the data supports, "all the
  /// thinking that was live is gone", and it is tested rather than assumed:
  /// the room it frees has to be roughly what the estimator says is entering.
  ///
  /// When it does not fit, the fallback aims at the room actually needed, the
  /// overhang plus what the estimator says is entering, and takes the subset
  /// that comes closest to it rather than the oldest segments until the
  /// overhang is covered. Taking the oldest first freed far more room than was
  /// needed and the sizer then handed that room to whatever entered: a 655
  /// token input came out at 8,627. What is left over now becomes an
  /// Unattributed segment graded E instead.
  ///
  /// Either way the request total stays exact. What this decides is which
  /// segments carry the loss, and that answer is graded `inferred`.
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

  /// The subset whose sizes come closest to the room that is needed, without
  /// going under the overhang, which it must cover or the request total stops
  /// being exact.
  ///
  /// Subset sum is not worth solving exactly here: the candidates are hundreds
  /// of segments and the answer is a hypothesis either way. Best fit in rank
  /// order takes whatever still fits, largest first, and then closes any
  /// remaining gap with the smallest segment that covers it.
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
      // The prefix is the number we are least sure of, so it is never spent to
      // make room. It is only ever reached to cover the overhang itself, below.
      if rank(segments[slot]) < prefixRank, tokens + size <= target {
        taken.append(slot)
        tokens += size
      } else {
        rest.append(slot)
      }
    }
    // The overhang is the hard floor. Close what is left with the smallest
    // segment that covers it, so the overshoot is the smallest available, and
    // look at the prefix only when nothing else can cover it.
    //
    // The prefix used to be one block per band, so reaching into it was rare.
    // It is now one block per tool and per system prompt block, sixty small
    // ones where there were four, and the smallest thing that covers a gap is
    // almost always one of those: a compaction took 14 of 15 tool blocks in a
    // test before this rule was split in two.
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

  /// The smallest candidate that covers the gap, or the largest there is.
  private static func choose(from slots: [Int], gap: Int, segments: [Segment]) -> Int? {
    let fitting = slots.filter { segments[$0].tokens.value >= gap }
    return fitting.min { segments[$0].tokens.value < segments[$1].tokens.value }
      ?? slots.max { segments[$0].tokens.value < segments[$1].tokens.value }
  }

  /// Whether the room the hypothesis frees is roughly what is entering. A
  /// factor of three either way: wide enough to accept a set that is clearly
  /// the right one, tight enough to reject a coincidence.
  private static func fits(_ implied: Int, _ estimate: Int) -> Bool {
    guard estimate > 0 else { return implied <= 64 }
    return implied <= estimate * 3 && implied * 3 >= estimate
  }

  /// Share of the freed room that may come back as Unattributed before the
  /// hypothesis is rejected. On a real session "all live thinking left" freed
  /// 22.3k tokens and 11.2k of them could not be handed to anything, which is
  /// a hypothesis that has been shown wrong by what followed it.
  static let unattributedLimit = 1.0 / 3

  /// Whether accepting the set would leave more than that share unaccounted
  /// for. What the entering blocks can take is what the estimator says they
  /// are; the rest of the room has nowhere to go and becomes Unattributed.
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

  /// Thinking goes first, then the oldest content, and the unobserved prefix
  /// last of all, because the prefix is the number we are least sure of.
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
    // When a whole set left, the tokens it frees beyond the overhang are the
    // room the entering content needed, not an error. What the entering
    // content cannot account for is reported as unattributed instead.
    result.overshoot = countsOvershoot ? max(0, result.tokens - target) : 0
    return result
  }

}
