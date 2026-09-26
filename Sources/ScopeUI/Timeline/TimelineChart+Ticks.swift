internal import ScopeCore

extension TimelineChart {
  static let tokenIntervals = 4
  static let requestIntervals = 4

  public static func tokenTicks(_ scale: Int) -> [Tick] {
    (0...tokenIntervals).map { part in
      Tick(
        TokenFormat.axis(scale * part / tokenIntervals),
        at: Double(part) / Double(tokenIntervals))
    }
  }

  public static func requestTicks(_ count: Int) -> [Tick] {
    guard count > 0 else { return [] }
    var ticks = [Tick("request 1", at: 0)]
    guard count > 1 else { return ticks }
    let step = roundStep(Double(count) / Double(requestIntervals))
    var number = step
    while number < count {
      if number > 1, Double(count - number) >= Double(step) / 2 {
        ticks.append(Tick(TokenFormat.count(number), at: Double(number - 1)))
      }
      number += step
    }
    ticks.append(Tick(TokenFormat.count(count), at: Double(count - 1)))
    return ticks
  }

  static func roundStep(_ raw: Double) -> Int {
    var power = 1
    while Double(power * 10) <= raw { power *= 10 }
    let choices = [1, 2, 5, 10].map { $0 * power }
    return choices.min { abs(Double($0) - raw) < abs(Double($1) - raw) } ?? power
  }
}
