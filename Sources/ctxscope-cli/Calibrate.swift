import Foundation
import ScopeCapture
import ScopeCore

/// Refits the estimator prior from the sessions on this machine, so the
/// numbers in `EstimatorRates.prior` are reproducible rather than something a
/// script once printed.
///
/// The fit pools the normal equations of every lane, which is the same
/// arithmetic each lane does for itself, only over more deltas.
enum CalibrateCommand {
  static func run(_ arguments: Arguments) throws {
    let adapter = Loader.adapter(arguments)
    let limit = arguments.integer("limit") ?? 25
    let sessions = try adapter.sessions()
      .sorted { $0.byteSize > $1.byteSize }
      .prefix(limit)

    var pooled = EstimatorCalibration()
    var lanes = 0
    var requests = 0
    for session in sessions {
      guard let captured = try? adapter.capture(session, includeSubagents: false) else { continue }
      for (_, fit) in captured.calibrations {
        pooled.merge(fit)
        lanes += 1
      }
      requests += captured.recording.mainLane?.snapshots.count ?? 0
      Console.error("fitted \(session.id.prefix(8)), \(pooled.sampleCount) deltas so far")
    }

    let rates = pooled.rates()
    Console.out("")
    Console.out(
      "fitted over \(pooled.sampleCount) derived deltas, "
        + "\(lanes) lanes, \(requests) requests, \(sessions.count) sessions")
    Console.out("")
    for contentClass in ContentClass.allCases {
      Console.out(
        "  " + TokenFormat.padRight(contentClass.rawValue, to: 8)
          + TokenFormat.pad(TokenFormat.ratio(rates.charactersPerToken(contentClass)), to: 8)
          + "  characters per token")
    }
    Console.out(
      "  " + TokenFormat.padRight("framing", to: 8)
        + TokenFormat.pad(TokenFormat.ratio(rates.tokensPerRequest, places: 1), to: 8)
        + "  tokens per request, "
        + "\(TokenFormat.ratio(EstimatorRates.tokensPerBlock, places: 0)) per block")
    Console.out("")
    Console.out("To make this the prior, put it into EstimatorRates.prior:")
    Console.out("  tokensPerCharacter: [")
    for contentClass in ContentClass.allCases {
      Console.out(
        "    .\(contentClass.rawValue): 1.0 / "
          + TokenFormat.ratio(rates.charactersPerToken(contentClass)) + ",")
    }
    Console.out("  ],")
    Console.out("  tokensPerRequest: " + TokenFormat.ratio(rates.tokensPerRequest, places: 1))
  }
}
