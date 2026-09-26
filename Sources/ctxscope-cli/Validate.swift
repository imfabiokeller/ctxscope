import Foundation
import ScopeCapture
import ScopeCore

enum ValidateCommand {
  static func run(_ arguments: Arguments) throws {
    let (session, captured) = try Loader.capture(arguments)
    let lanes =
      arguments.value("lane") != nil
      ? [try Loader.lane(captured, arguments)] : captured.recording.lanes
    let results = lanes.map(Validator.run)

    if arguments.has("json") {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(results)
      Console.out(String(decoding: data, as: UTF8.self))
      exit(results.allSatisfy(\.passed) ? 0 : 1)
    }

    Console.out("session  \(session.id)")
    Console.out("project  \(session.project)")
    Console.out("")
    for result in results {
      let lane = lanes.first { $0.id == result.lane }
      Console.out(
        "lane \(result.lane.rawValue)"
          + (lane?.agentType.map { " (\($0))" } ?? "")
          + "  \(result.requestCount) requests, \(result.segmentCount) segments")
      for check in result.checks {
        Console.out("  \(check.passed ? "pass" : "FAIL")  \(check.name): \(check.detail)")
      }
      if !result.mismatches.isEmpty {
        for mismatch in result.mismatches.prefix(5) {
          Console.out(
            "        \(RequestNumber.name(mismatch.request)): measured \(mismatch.measured), "
              + "reconstructed \(mismatch.reconstructed), off by \(mismatch.difference)")
        }
      }
      Console.out(
        "  estimator residual before normalization, against what entered: median "
          + TokenFormat.finePercent(result.residualMedian)
          + ", p90 " + TokenFormat.finePercent(result.residualP90)
          + ", max " + TokenFormat.finePercent(result.residualMax))
      Console.out(
        "  composition error, every miss added up over every token that "
          + "entered: " + TokenFormat.finePercent(result.compositionError))
      for event in result.events {
        Console.out(
          "  event  \(RequestNumber.name(event.request)): \(event.kind.rawValue), "
            + "\(TokenFormat.tokens(event.tokens)), \(event.detail)")
      }
      Console.out("  " + rates(result.rates))
      Console.out("")
    }
    let failed = results.filter { !$0.passed }
    Console.out(
      failed.isEmpty
        ? "all \(results.count) lanes pass"
        : "\(failed.count) of \(results.count) lanes fail")
    exit(failed.isEmpty ? 0 : 1)
  }

  static func rates(_ rates: EstimatorRates) -> String {
    let parts = ContentClass.allCases.map {
      "\($0.rawValue) \(TokenFormat.ratio(rates.charactersPerToken($0)))"
    }
    return "characters per token, fitted on \(rates.samples) deltas: "
      + parts.joined(separator: ", ")
      + "; framing \(TokenFormat.ratio(rates.tokensPerRequest, places: 0)) tokens per request, "
      + "\(TokenFormat.ratio(EstimatorRates.tokensPerBlock, places: 0)) per block"
  }
}
