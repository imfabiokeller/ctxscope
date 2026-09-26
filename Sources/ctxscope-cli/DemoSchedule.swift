import Foundation

struct DemoSchedule {
  let responses: [Date]

  static func story(gaps: [Double], start: Date) -> DemoSchedule {
    var times: [Date] = []
    var time = start
    for (index, gap) in gaps.enumerated() {
      if index > 0 { time = time.addingTimeInterval(gap) }
      times.append(time)
    }
    return DemoSchedule(responses: times)
  }

  static func story(gaps: [Double], end: Date) -> DemoSchedule {
    let span = gaps.dropFirst().reduce(0, +)
    return story(gaps: gaps, start: end.addingTimeInterval(-span))
  }

  // The pause before the first live request stays the story's, so a cache break
  // the story puts there still happens.
  static func live(gaps: [Double], batch: Int, now: Date, seconds: Double) -> DemoSchedule {
    let remaining = max(1, gaps.count - batch)
    let interval = max(0.2, seconds / Double(remaining))
    var times = story(gaps: Array(gaps.prefix(batch)), start: .distantPast).responses
    let firstLive = now.addingTimeInterval(interval)
    let pause = batch < gaps.count ? max(gaps[batch], interval) : interval
    let shift = firstLive.addingTimeInterval(-pause).timeIntervalSince(times.last ?? firstLive)
    times = times.map { $0.addingTimeInterval(shift) }
    for position in 0..<(gaps.count - batch) {
      times.append(firstLive.addingTimeInterval(Double(position) * interval))
    }
    return DemoSchedule(responses: times)
  }

  func times(of index: Int, waits: Bool = false) -> DemoTimes {
    let response = responses[index]
    let before = index > 0 ? response.timeIntervalSince(responses[index - 1]) : 20
    let after =
      index + 1 < responses.count ? responses[index + 1].timeIntervalSince(response) : 4
    return DemoTimes(
      inputs: response.addingTimeInterval(-min(before * 0.35, 6)),
      response: response,
      results: response.addingTimeInterval(waits ? min(after * 0.9, 150) : min(after * 0.3, 15)))
  }
}

struct DemoTimes {
  let inputs: Date
  let response: Date
  let results: Date

  func subagent(_ position: Int, of count: Int) -> DemoTimes {
    let span = results.timeIntervalSince(response)
    let step = span / Double(count + 1)
    let start = response.addingTimeInterval(step * Double(position) + step * 0.2)
    return DemoTimes(
      inputs: start, response: start.addingTimeInterval(step * 0.5),
      results: start.addingTimeInterval(step * 0.8))
  }

  static func stamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}
