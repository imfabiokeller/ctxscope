/// Length zones: how long a context is, in five steps, which the CLI reports
/// with every request.
///
/// A zone is an absolute length in tokens, not a share of the window. A
/// context of 790k tokens is a long context whatever window it sits in, and
/// the question a zone answers is how long this one is, not how much room is
/// left. Where the harness compacts answers a different question.
///
/// A zone is a color and two numbers. It carries no word, because there is no
/// honest one: what is known is that models recall less reliably as a context
/// grows, and where the steps are.
public enum LengthZone: String, Sendable, Codable, CaseIterable, Comparable {
  case first
  case second
  case third
  case fourth
  case fifth

  /// Where it sits in the ramp, from calmest to most alarming.
  public var step: Int { LengthZone.allCases.firstIndex(of: self) ?? 0 }

  public static func < (left: LengthZone, right: LengthZone) -> Bool {
    left.step < right.step
  }
}

/// Where one model's zones start and end.
///
/// Data, not constants scattered through the drawing code: there is one set
/// of defaults, a model that behaves differently gets its own entry, and a
/// measured curve from needle probes would replace the numbers without
/// touching anything that draws them.
public struct ZoneScale: Sendable, Codable, Hashable {
  /// The four boundaries between the five zones, in tokens, ascending. The
  /// fifth zone has no upper bound.
  public let steps: [Int]

  public init(steps: [Int]) {
    var sorted = steps.sorted()
    // One boundary per gap between zones, whatever was passed in.
    while sorted.count < LengthZone.allCases.count - 1 {
      sorted.append(sorted.last ?? 0)
    }
    self.steps = Array(sorted.prefix(LengthZone.allCases.count - 1))
  }

  /// The defaults, and what every model gets until one is measured.
  /// Five steps, because one zone covering everything above 120k said the
  /// same thing about a 130k context and a 900k one.
  public static let `default` = ZoneScale(steps: [50_000, 120_000, 200_000, 500_000])

  /// Per model id. Empty until a model is measured: the default answers for
  /// everything else, and nothing here is a guess dressed as a measurement.
  public static let perModel: [String: ZoneScale] = [:]

  public static func forModel(_ model: String) -> ZoneScale {
    perModel[model] ?? .default
  }

  public func zone(ofLength tokens: Int) -> LengthZone {
    for (slot, step) in steps.enumerated() where tokens <= step {
      return LengthZone.allCases[slot]
    }
    return LengthZone.allCases[LengthZone.allCases.count - 1]
  }

  /// Where a zone starts, in tokens. The one place the boundaries are read
  /// from, so a ruler and a lookup can never disagree.
  public func lowerBound(of zone: LengthZone) -> Int {
    zone.step == 0 ? 0 : steps[zone.step - 1]
  }

  /// Where a zone ends, in tokens. `nil` for the zone that has no end.
  public func upperBound(of zone: LengthZone) -> Int? {
    zone.step < steps.count ? steps[zone.step] : nil
  }
}
