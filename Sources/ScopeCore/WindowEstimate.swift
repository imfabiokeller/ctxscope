/// How large the context window was.
///
/// Nothing in a transcript says it. What a transcript does give is a proven
/// lower bound: the largest prompt the model accepted, and the size a
/// compaction reported it was compacting. On this machine the peaks run to
/// 994421, 897705 and 878570 tokens, so a 200000 default would have printed
/// fills of several hundred percent.
///
/// So the window is inferred as the smallest window we know of that is at
/// least as large as what was observed, it is graded D, and it says "at
/// least". A setting overrides it, and then it is measured by fiat.
/// The largest prompt each model was ever seen to hold, across the sessions
/// that have been read.
///
/// A session that never filled its window reports the next size down, and a
/// live 1M session therefore looks nearly full while it approaches 200k and
/// then jumps. What another session of the same model was seen to hold is not
/// proof of this session's window, since the larger window is a flag a session
/// is started with, so it raises the bound and grades it E.
public struct ModelWindowHints: Sendable, Codable, Hashable {
  public private(set) var peaks: [String: Int] = [:]

  public init(peaks: [String: Int] = [:]) {
    self.peaks = peaks
  }

  public mutating func observe(model: String, peak: Int) {
    guard !model.isEmpty, peak > 0 else { return }
    peaks[model] = max(peaks[model] ?? 0, peak)
  }

  /// Takes in everything one lane was seen to hold.
  public mutating func observe(_ lane: Lane) {
    for snapshot in lane.snapshots {
      observe(model: snapshot.model, peak: snapshot.usage.promptTotal)
    }
  }

  public func peak(for model: String) -> Int { peaks[model] ?? 0 }
}

public struct WindowEstimate: Sendable, Codable, Hashable {
  /// Windows the harness is known to run. A session can only have used one
  /// that is at least as large as its largest request.
  ///
  /// 500,000 used to be in this list with nothing behind it. No session on
  /// this machine ran such a window, and having it there made every session
  /// between 200k and 500k report a bound nobody could stand behind.
  public static let known = [200_000, 1_000_000]

  public let tokens: Int
  public let grade: Grade
  /// True when the number is the smallest window that fits, rather than a
  /// window anyone confirmed.
  public let isLowerBound: Bool
  /// The largest prompt actually seen, which is what the bound rests on.
  public let observedPeak: Int
  /// Where the harness compacted, when it compacted. Otherwise nil, and the
  /// zone ruler falls back to a labeled default.
  public let observedCompactionAt: Int?

  public init(
    tokens: Int,
    grade: Grade,
    isLowerBound: Bool,
    observedPeak: Int,
    observedCompactionAt: Int? = nil
  ) {
    self.tokens = tokens
    self.grade = grade
    self.isLowerBound = isLowerBound
    self.observedPeak = observedPeak
    self.observedCompactionAt = observedCompactionAt
  }

  /// A window the caller set. Nothing is inferred and nothing is hedged.
  public static func given(_ tokens: Int) -> WindowEstimate {
    WindowEstimate(
      tokens: tokens, grade: .measured, isLowerBound: false, observedPeak: 0)
  }

  /// The smallest known window that fits everything this lane was seen to
  /// hold, and everything another session of the same model was seen to hold.
  public init(
    observing snapshots: [Snapshot],
    _ compactions: [CompactionEvent],
    hints: ModelWindowHints = ModelWindowHints()
  ) {
    let peak = max(
      snapshots.map(\.usage.promptTotal).max() ?? 0,
      compactions.map(\.preTokens).max() ?? 0
    )
    let hinted = snapshots.map { hints.peak(for: $0.model) }.max() ?? 0
    let fitted = Self.known.first { $0 >= max(peak, hinted) } ?? max(peak, hinted)
    self.init(
      tokens: max(fitted, Self.known[0]),
      // Only this lane's own peak is arithmetic. A bound that rests on what
      // another session held is a hint about a flag, not a measurement.
      grade: hinted > peak && fitted > (Self.known.first { $0 >= peak } ?? peak)
        ? .estimated : .derived,
      isLowerBound: true,
      observedPeak: peak,
      observedCompactionAt: compactions.map(\.preTokens).max()
    )
  }

  /// Share of the window a request filled. Never above one: a fill over the
  /// window would mean the window is wrong, and the window is the estimate.
  public func fill(_ tokens: Int) -> Double {
    guard self.tokens > 0 else { return 0 }
    return min(1, Double(tokens) / Double(self.tokens))
  }

  /// Where the harness compacts, when the lane never compacted and there is
  /// nothing to measure. Both compactions observed on this machine fired at
  /// about 99.9 percent of the window.
  public static let defaultCompactShare = 0.90

  /// Where the harness compacts. Measured when this lane compacted, and a
  /// labeled default otherwise: the two compactions on this machine both
  /// fired at about 99.9 percent of a 1M window, so the old 83.5 percent
  /// constant was wrong at that scale.
  public var autoCompactTokens: Tokens {
    if let observed = observedCompactionAt, observed > 0 {
      return Tokens(observed, .measured)
    }
    return Tokens(Int(Double(tokens) * Self.defaultCompactShare), .estimated)
  }

  public var label: String {
    isLowerBound ? "at least \(TokenFormat.axis(tokens))" : TokenFormat.axis(tokens)
  }
}
