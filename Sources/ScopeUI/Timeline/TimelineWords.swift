internal import ScopeCore

enum TimelineWords {
  static let chart = "Context per request"
  static let cacheBreak = "cache break"
  static let cost = "cost"
  static let prompts = "By prompt"
  static let breaks = "Cache breaks"
  static let number = "#"
  static let prompt = "Prompt"
  static let requests = "Requests"
  static let added = "Context added"
  static let costColumn = "Cost"
  static let breaksColumn = "Cache breaks"

  static func band(_ row: PromptRow) -> String {
    let noun = row.requests.count == 1 ? "request" : "requests"
    return "Prompt \(row.number) · \(noun) \(row.range)"
  }

  static func breaks(_ marks: [TimelineChart.Break]) -> String {
    guard let first = marks.first, let last = marks.last else { return "" }
    let requests = marks.map { "\(RequestNumber.of($0.column))" }.joined(separator: ", ")
    if marks.count == 1 { return "Cache break \(first.number) · request \(requests)" }
    return "Cache breaks \(first.number)\u{2013}\(last.number) · requests \(requests)"
  }
}
