import Foundation
import ScopeCapture
import ScopeCore

/// What is in the context at one request, what it cost to carry, and how much
/// of it was referenced. Every number carries its grade.
enum AnalyzeCommand {
  static func run(_ arguments: Arguments) throws {
    let (session, captured) = try Loader.capture(arguments)
    let lane = try Loader.lane(captured, arguments)
    guard !lane.snapshots.isEmpty else {
      throw CLIError.usage("lane \(lane.id.rawValue) has no requests")
    }
    // `--at` is the number a person reads off the window, which counts from
    // one. Without it, the newest request.
    let at = min(
      try arguments.requestNumber("at") ?? (lane.snapshots.count - 1),
      lane.snapshots.count - 1)

    let references = Loader.references(captured, lane)
    let tally = TallyAnalyzer.run(lane)
    let cache = CacheAnalyzer.run(lane)
    let carry = CarryCostAnalyzer.run(lane, references: references)
    let duplication = DuplicationAnalyzer.run(lane)
    let segmentCache = SegmentCacheAnalyzer.run(lane)
    let summary = ReferenceAnalyzer.run(lane, references: references, at: at)
    let figures = WindowFigures(
      lane: lane, at: at, references: references, tally: tally, cache: cache,
      segmentCache: segmentCache)

    if arguments.has("json") {
      try emitJSON(
        lane: lane, tally: tally, cache: cache, carry: carry, summary: summary,
        figures: figures)
      return
    }

    let entry = tally.perRequest[at]
    Console.out("session  \(session.id)  \(session.title ?? "")")
    Console.out(
      "lane     \(lane.id.rawValue)"
        + (lane.agentType.map { " (\($0))" } ?? "")
        + ", \(lane.snapshots.count) requests, model \(lane.snapshots[at].model)")
    // The label column already says what the number is, the way the window's
    // footer does.
    Console.out("request  \(RequestNumber.counter(at, of: lane.snapshots.count))")
    Console.out("")
    Console.out(
      "in context   \(TokenFormat.tokens(entry.total))"
        + "   fill \(TokenFormat.percent(entry.fill))"
        + " of \(lane.window.label) \(lane.window.grade.rawValue)"
        + "   step \(entry.zone.step + 1)")
    Console.out(
      "reused       \(TokenFormat.tokens(summary.referencedTokens))"
        + "   ratio \(TokenFormat.percent(summary.ratio))"
        + " [\(TokenFormat.percent(summary.interval.lowerBound))"
        + " to \(TokenFormat.percent(summary.interval.upperBound))]"
        + "   n_eff \(TokenFormat.ratio(summary.effectiveSampleSize, places: 0))"
        + "   interval covers \(summary.intervalCovers)")
    Console.out(
      "input side   \(TokenFormat.tokens(summary.inputReferencedTokens))"
        + "   ratio \(TokenFormat.percent(summary.inputRatio))"
        + " of \(TokenFormat.tokens(summary.inputAssessedTokens))"
        + "   what the model did not write itself")
    Console.out(
      "not assessable \(TokenFormat.tokens(summary.notAssessableTokens))"
        + "   prefix share \(TokenFormat.percent(entry.prefixShare.value))"
        + " \(entry.prefixShare.grade.rawValue)"
        + "   cache hit \(TokenFormat.percent(cache.perRequest[at].hit))"
        + " \(cache.perRequest[at].readTokens.grade.rawValue)")
    Console.out(
      "position     first \(TokenFormat.percent(summary.positionalShare[0]))"
        + "  middle \(TokenFormat.percent(summary.positionalShare[1]))"
        + "  last \(TokenFormat.percent(summary.positionalShare[2]))"
        + "   (reused share by third of the context)")
    Console.out("method       \(references.method.summary)")
    Console.out("prefix split \(prefixSource(lane))")
    Console.out("")

    Console.out("composition")
    for band in BandRegistry.ordered {
      let value = entry.byBand[BandRegistry.position(of: band)]
      guard value.value > 0 else { continue }
      let share = entry.total.value > 0 ? Double(value.value) / Double(entry.total.value) : 0
      Console.out(
        "  " + TokenFormat.padRight(band.rawValue, to: 6)
          + TokenFormat.padRight(BandRegistry.label(of: band), to: 18)
          + TokenFormat.pad(TokenFormat.tokens(value), to: 10)
          + TokenFormat.pad(TokenFormat.percent(share), to: 6)
          + "  " + bar(share))
    }
    Console.out("")
    for line in figures.lines { Console.out(line) }
    Console.out("")

    Console.out(
      "carry cost   \(TokenFormat.tokens(carry.totalCarryTokens)) token-requests"
        + ", max unused age \(carry.maxUnreferencedAge) requests")
    Console.out("largest unused, top six")
    for cost in carry.top() {
      Console.out(
        "  " + TokenFormat.padRight(cost.band.rawValue, to: 6)
          + TokenFormat.padRight(cost.label, to: 30)
          + TokenFormat.pad(TokenFormat.tokens(cost.tokens), to: 10)
          + TokenFormat.pad("x\(cost.requestsCarried)", to: 6)
          + TokenFormat.pad(
            cost.unreferencedCarryTokens.map(TokenFormat.tokens) ?? "n/a", to: 11)
          + "  "
          + (cost.isAssessable
            ? "reused \(TokenFormat.percent(cost.referencedShare ?? 0))"
            : "not assessable"))
    }
    Console.out("")

    let rewritten = segmentCache.perSegment.filter { $0.writes > 1 }
    Console.out(
      "cache        \(cache.busts.count) busts, "
        + "\(TokenFormat.tokens(cache.totalWritten)) written, "
        + "\(TokenFormat.tokens(cache.totalRead)) read")
    for found in figures.breaks.prefix(4) {
      let bust = found.bust
      Console.out(
        "  \(RequestNumber.name(bust.request)): "
          + "\(TokenFormat.tokens(bust.rewrittenTokens)) rewritten, "
          + bust.cause.rawValue + ", +" + TokenFormat.dollars(found.extra))
    }
    if !rewritten.isEmpty {
      let most = rewritten.max { $0.writes < $1.writes }
      Console.out(
        "  \(rewritten.count) segments written more than once, most "
          + "\(most?.writes ?? 0) times")
    }
    let compaction = CompactionAnalyzer.run(lane)
    if compaction.count > 0 {
      Console.out("")
      Console.out("compaction")
      for summary in compaction.compactions {
        Console.out(
          "  \(RequestNumber.name(summary.event.atRequest)) (\(summary.event.trigger)): "
            + "\(TokenFormat.tokens(Tokens(summary.event.preTokens, .measured))) to "
            + "\(TokenFormat.tokens(Tokens(summary.event.postTokens, .measured)))"
            + ", \(summary.survivingSegments) segments survived, "
            + "\(TokenFormat.tokens(summary.droppedTokens)) dropped"
            + (summary.disagreement > 1000
              ? ", \(TokenFormat.tokens(summary.disagreement)) more than the reconstruction saw"
              : ""))
      }
    }
    if !duplication.groups.isEmpty {
      Console.out("")
      Console.out(
        "duplication  \(duplication.groups.count) groups, "
          + "\(TokenFormat.tokens(duplication.wastedCarryTokens)) token-requests on copies")
    }
  }

  /// Where the split of the unobserved prefix came from, and how many blocks
  /// each source is worth. The prior is four numbers somebody chose; a report
  /// is the harness counting its own prompt.
  private static func prefixSource(_ lane: Lane) -> String {
    let blocks = lane.segments.filter {
      $0.born == 0 && BandRegistry.family(of: $0.band) == .prefix
    }
    let recorded = blocks.count { $0.characters > 0 }
    return lane.prefixSource.rawValue
      + ", \(blocks.count) blocks, \(recorded) of them with recorded text"
      + (lane.stats.contextReports > 1
        ? ", \(lane.stats.contextReports) context reports in the lane" : "")
  }

  private static func bar(_ share: Double) -> String {
    String(repeating: "#", count: max(0, min(40, Int((share * 40).rounded()))))
  }

  private static func emitJSON(
    lane: Lane,
    tally: Tally,
    cache: CacheAnalysis,
    carry: CarryCostAnalysis,
    summary: ReferenceSummary,
    figures: WindowFigures
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let payload = AnalysisPayload(
      lane: lane.id,
      window: lane.window,
      bands: BandRegistry.ordered.map(\.rawValue),
      tally: tally,
      cache: cache,
      unreferencedCost: carry.top(12),
      reference: summary,
      compactions: lane.compactions,
      events: lane.events,
      rates: lane.calibration,
      figures: figures
    )
    Console.out(String(decoding: try encoder.encode(payload), as: UTF8.self))
  }
}

struct AnalysisPayload: Encodable {
  let lane: LaneID
  let window: WindowEstimate
  let bands: [String]
  let tally: Tally
  let cache: CacheAnalysis
  let unreferencedCost: [SegmentCost]
  let reference: ReferenceSummary
  let compactions: [CompactionEvent]
  let events: [LaneEvent]
  let rates: EstimatorRates
  let figures: WindowFigures
}
