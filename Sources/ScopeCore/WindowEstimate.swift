public struct ModelWindowHints: Sendable, Codable, Hashable {
  public private(set) var peaks: [String: Int] = [:]

  public init(peaks: [String: Int] = [:]) {
    self.peaks = peaks
  }

  public mutating func observe(model: String, peak: Int) {
    guard !model.isEmpty, peak > 0 else { return }
    peaks[model] = max(peaks[model] ?? 0, peak)
  }

  public mutating func observe(_ lane: Lane) {
    for snapshot in lane.snapshots {
      observe(model: snapshot.model, peak: snapshot.usage.promptTotal)
    }
  }

  public func peak(for model: String) -> Int { peaks[model] ?? 0 }
}

public struct WindowEstimate: Sendable, Codable, Hashable {
  public static let known = [200_000, 1_000_000]

  public let tokens: Int
  public let grade: Grade
  public let isLowerBound: Bool
  public let observedPeak: Int
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

  public static func given(_ tokens: Int) -> WindowEstimate {
    WindowEstimate(
      tokens: tokens, grade: .measured, isLowerBound: false, observedPeak: 0)
  }

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
      // A bound resting on another session's peak is a hint about a flag, so it is graded E.
      grade: hinted > peak && fitted > (Self.known.first { $0 >= peak } ?? peak)
        ? .estimated : .derived,
      isLowerBound: true,
      observedPeak: peak,
      observedCompactionAt: compactions.map(\.preTokens).max()
    )
  }

  public func fill(_ tokens: Int) -> Double {
    guard self.tokens > 0 else { return 0 }
    return min(1, Double(tokens) / Double(self.tokens))
  }

  // A conservative guess for a lane that never compacted; observed
  // compactions fired later, near 99.9 percent.
  public static let defaultCompactShare = 0.90

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
