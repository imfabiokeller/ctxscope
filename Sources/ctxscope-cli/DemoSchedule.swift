import Foundation

/// When each request of the main lane is answered, and so when everything
/// around it is written.
struct DemoSchedule {
  /// The time of each request's response, in order.
  let responses: [Date]

  /// The story's own pace, starting at `start`.
  static func story(gaps: [Double], start: Date) -> DemoSchedule {
    var times: [Date] = []
    var time = start
    for (index, gap) in gaps.enumerated() {
      if index > 0 { time = time.addingTimeInterval(gap) }
      times.append(time)
    }
    return DemoSchedule(responses: times)
  }

  /// The story's pace, ending at `end`.
  static func story(gaps: [Double], end: Date) -> DemoSchedule {
    let span = gaps.dropFirst().reduce(0, +)
    return story(gaps: gaps, start: end.addingTimeInterval(-span))
  }

  /// The first `batch` requests at the story's pace and in the past, the rest
  /// one every `seconds / remaining` from `now` on. The pause in front of the
  /// first live request is the story's, so a break the story puts there still
  /// happens.
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

  /// When the entries of request `index` are written. A request that starts
  /// a subagent waits most of the pause after it for the run to finish.
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

/// The three moments of one request.
struct DemoTimes {
  /// The prompt and the attachments in front of the request.
  let inputs: Date
  let response: Date
  /// The tool results, and the end of any subagent run the request started.
  let results: Date

  /// The same span divided among `count` requests of a subagent run.
  func subagent(_ position: Int, of count: Int) -> DemoTimes {
    let span = results.timeIntervalSince(response)
    let step = span / Double(count + 1)
    let start = response.addingTimeInterval(step * Double(position) + step * 0.2)
    return DemoTimes(
      inputs: start, response: start.addingTimeInterval(step * 0.5),
      results: start.addingTimeInterval(step * 0.8))
  }

  /// ISO 8601 with milliseconds, the way transcripts write it.
  static func stamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}
