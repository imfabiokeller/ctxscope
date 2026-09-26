public enum LengthZone: String, Sendable, Codable, CaseIterable, Comparable {
  case first
  case second
  case third
  case fourth
  case fifth

  public var step: Int { LengthZone.allCases.firstIndex(of: self) ?? 0 }

  public static func < (left: LengthZone, right: LengthZone) -> Bool {
    left.step < right.step
  }
}

public struct ZoneScale: Sendable, Codable, Hashable {
  public let steps: [Int]

  public init(steps: [Int]) {
    var sorted = steps.sorted()
    while sorted.count < LengthZone.allCases.count - 1 {
      sorted.append(sorted.last ?? 0)
    }
    self.steps = Array(sorted.prefix(LengthZone.allCases.count - 1))
  }

  public static let `default` = ZoneScale(steps: [50_000, 120_000, 200_000, 500_000])

  /// Empty until a model is measured: nothing here is a guess.
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

  public func lowerBound(of zone: LengthZone) -> Int {
    zone.step == 0 ? 0 : steps[zone.step - 1]
  }

  public func upperBound(of zone: LengthZone) -> Int? {
    zone.step < steps.count ? steps[zone.step] : nil
  }
}
