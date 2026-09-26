/// The checks behind `ctxscope validate`, and the same ones the test suite
/// runs. The headline is the first one: segment sizes must sum to the API's
/// own number on every request, exactly.

public struct RequestMismatch: Sendable, Codable, Hashable {
  public let request: Int
  public let measured: Int
  public let reconstructed: Int

  public var difference: Int { reconstructed - measured }
}

public struct ValidationCheck: Sendable, Codable {
  public let name: String
  public let passed: Bool
  public let detail: String
}

public struct LaneValidation: Sendable, Codable {
  public let lane: LaneID
  public let requestCount: Int
  public let segmentCount: Int
  public let mismatches: [RequestMismatch]
  public let residualMedian: Double
  public let residualP90: Double
  public let residualMax: Double
  /// Every miss the estimator made, added up without cancelling, over every
  /// token that ever entered. Misses do not cancel: each one stays with the
  /// segment it was made on for as long as that segment is carried, so this
  /// is the honest bound on how wrong the composition is.
  public let compositionError: Double
  public let rates: EstimatorRates
  public let prefixTokens: Int
  public let stats: CaptureStats
  /// Everything that happened to the lane's context, each with the grade of
  /// the claim: what the harness recorded, and what the reconstruction had to
  /// decide for itself.
  public let events: [LaneEvent]
  public let checks: [ValidationCheck]

  public var passed: Bool { checks.allSatisfy(\.passed) }
}

public enum Validator {
  public static func run(_ lane: Lane) -> LaneValidation {
    var mismatches: [RequestMismatch] = []
    let tally = TallyAnalyzer.run(lane)
    for entry in tally.perRequest {
      let reconstructed = entry.byBand.reduce(0) { $0 + $1.value }
      if reconstructed != entry.total.value {
        mismatches.append(
          RequestMismatch(
            request: entry.request,
            measured: entry.total.value,
            reconstructed: reconstructed
          )
        )
      }
    }

    let residuals = lane.snapshots.map(\.estimatorResidual).sorted()
    let missed = lane.snapshots.reduce(0) { $0 + abs($1.residualTokens) }
    let appended = lane.snapshots.reduce(0) { $0 + $1.appendedTokens }
    let prefix = lane.segments
      .filter { $0.born == 0 && BandRegistry.family(of: $0.band) == .prefix }
      .reduce(0) { $0 + $1.tokens.value }

    var checks: [ValidationCheck] = []
    checks.append(
      ValidationCheck(
        name: "totals equal API usage",
        passed: mismatches.isEmpty,
        detail: mismatches.isEmpty
          ? "\(lane.snapshots.count) of \(lane.snapshots.count) requests exact"
          : "\(mismatches.count) of \(lane.snapshots.count) requests off, "
            + "worst \(mismatches.map { abs($0.difference) }.max() ?? 0) tokens"
      )
    )
    let negative = lane.segments.filter { $0.tokens.value < 0 }
    checks.append(
      ValidationCheck(
        name: "no segment has a negative size",
        passed: negative.isEmpty,
        detail: negative.isEmpty
          ? "\(lane.segments.count) segments"
          : "\(negative.count) segments below zero tokens"
      )
    )
    // A block that ends up at the floor did not get a size of its own: the
    // measured delta ran out before it was reached, so it was pinned at one
    // token or at zero. Counting only the zeros hides the problem, because the
    // floor is one. A lane where this happens often is a lane where something
    // upstream is claiming tokens that are not its own.
    let floored = lane.segments.filter { $0.characters > 0 && $0.tokens.value <= Segment.floor }
    let flooredShare =
      lane.segments.isEmpty ? 0 : Double(floored.count) / Double(lane.segments.count)
    checks.append(
      ValidationCheck(
        name: "blocks the measured delta could pay for",
        passed: flooredShare < 0.02,
        detail: (floored.isEmpty
          ? "all \(lane.segments.count) segments"
          : "\(floored.count) of \(lane.segments.count) segments at the floor "
            + "(\(TokenFormat.finePercent(flooredShare)))")
          + (lane.stats.unfinishedResponses > 0
            ? ", \(lane.stats.unfinishedResponses) of \(lane.snapshots.count) responses have "
              + "no stop reason and were estimated" : "")
          + (lane.stats.rejectedMeasurements > 0
            ? ", \(lane.stats.rejectedMeasurements) finished totals refused as implausible" : "")
      )
    )
    // Parallel calls put every sibling result off the parent chain. If those
    // results are not put back, their tokens are silently spread over their
    // neighbours and the judge never sees them.
    checks.append(
      ValidationCheck(
        name: "tool calls brought their results",
        passed: lane.stats.toolCallsWithoutResult == 0,
        detail: lane.stats.toolCalls == 0
          ? "no tool calls"
          : "\(lane.stats.toolCallsWithResult) of \(lane.stats.toolCalls) calls have their result"
      )
    )
    // Content that left with nothing in the transcript saying so. Exactness
    // is unaffected, but which segments carried the loss is a hypothesis, so
    // the reader is told how much of the lane rests on one.
    let retired = lane.stats.inferredRetirementTokens
    checks.append(
      ValidationCheck(
        name: "content that left without being recorded",
        passed: true,
        detail: lane.stats.inferredRetirements == 0
          ? "none"
          : "\(lane.stats.inferredRetirements) segments, "
            + "\(TokenFormat.tokens(retired)) tokens, overshoot "
            + "\(TokenFormat.tokens(lane.stats.inferredRetirementOvershoot)) tokens, "
            + "\(TokenFormat.tokens(lane.stats.unattributedTokens)) tokens unattributed"
      )
    )
    // What the input itself was like. A chain that restarts takes every
    // segment with it, so a lane with many of them is one whose history is
    // missing rather than one that was analysed badly.
    checks.append(
      ValidationCheck(
        name: "the transcript read cleanly",
        passed: lane.stats.chainRestarts == 0 && lane.stats.skippedLines == 0,
        detail: (lane.stats.chainRestarts == 0 && lane.stats.skippedLines == 0
          ? "no unparseable lines, no chain restarts"
          : "\(lane.stats.skippedLines) unparseable lines, "
            + "\(lane.stats.chainRestarts) chain restarts")
          + ", \(lane.stats.heldEntries) entries held in memory"
      )
    )
    let backwards = lane.segments.filter { ($0.died ?? Int.max) <= $0.born }
    checks.append(
      ValidationCheck(
        name: "segment lives are ordered",
        passed: backwards.isEmpty,
        detail: backwards.isEmpty
          ? "no segment dies before it is born"
          : "\(backwards.count) segments die at or before birth"
      )
    )
    checks.append(
      ValidationCheck(
        name: "prefix is derivable",
        passed: prefix > 0 || lane.snapshots.isEmpty,
        detail: "prefix \(TokenFormat.tokens(prefix)) tokens"
      )
    )
    // This one is about the input, not about ctxscope: when the API's own
    // usage fields disagree with each other, every number derived from them
    // is uncertain and the reader should know.
    let badUsage = lane.snapshots.filter {
      $0.usage.cacheCreationTokens != $0.usage.ephemeral1hTokens + $0.usage.ephemeral5mTokens
    }
    // A request that took two attempts reports an aggregate assembled from
    // both, and its fields can then disagree with each other. That is an
    // explanation, not a failure, so the check only fails when there is no
    // explanation.
    let unexplained = badUsage.filter { $0.usage.iterations < 2 }
    checks.append(
      ValidationCheck(
        name: "cache creation adds up",
        passed: unexplained.isEmpty,
        detail: badUsage.isEmpty
          ? "1h plus 5m equals cache creation on all \(lane.snapshots.count) requests"
          : "the API's own fields disagree on \(badUsage.count) requests, first at "
            + "\(badUsage[0].index): cache creation says "
            + "\(badUsage[0].usage.cacheCreationTokens), the breakdown says "
            + "\(badUsage[0].usage.ephemeral1hTokens + badUsage[0].usage.ephemeral5mTokens)"
            + (unexplained.isEmpty
              ? ", explained by a fallback across "
                + "\(badUsage[0].usage.iterationModels.joined(separator: " and "))"
              : ", with no fallback to explain it")
      )
    )

    if let report = lane.contextReport {
      checks.append(harnessCheck(lane, report: report, tally: tally))
    }

    return LaneValidation(
      lane: lane.id,
      requestCount: lane.snapshots.count,
      segmentCount: lane.segments.count,
      mismatches: mismatches,
      residualMedian: percentile(residuals, 0.5),
      residualP90: percentile(residuals, 0.9),
      residualMax: residuals.last ?? 0,
      compositionError: appended > 0 ? Double(missed) / Double(appended) : 0,
      rates: lane.calibration,
      prefixTokens: prefix,
      stats: lane.stats,
      events: lane.events,
      checks: checks
    )
  }

  private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * fraction)))
    return sorted[index]
  }

  /// Band estimates against the harness's own
  /// `/context` report on the same session, with the error per category.
  ///
  /// It is a comparison, not an invariant. The harness counted the same prompt
  /// with its own tokenizer, so a few percent either way says the estimator is
  /// working; the check only fails when the two disagree about the whole
  /// request by more than a quarter, which would mean something structural is
  /// wrong rather than an estimate being off.
  static func harnessCheck(
    _ lane: Lane, report: ContextReport, tally: Tally
  ) -> ValidationCheck {
    let at = max(0, min(report.request, tally.perRequest.count - 1))
    guard let entry = tally.perRequest.indices.contains(at) ? tally.perRequest[at] : nil else {
      return ValidationCheck(
        name: "bands against the harness's own report", passed: true,
        detail: "the report names a request this lane does not have")
    }
    func ours(_ band: Band) -> Int { entry.byBand[BandRegistry.position(of: band)].value }
    let prefix = BandRegistry.bands(in: .prefix).reduce(0) { $0 + ours($1) }
    let rows: [(String, Int, Int)] = [
      ("sys", ours(.sys), report.systemPrompt),
      ("tools", ours(.tools), report.systemTools),
      ("mcp", ours(.mcp), report.mcpTools),
      ("mem", ours(.mem), report.memoryFiles),
      ("the rest", entry.total.value - prefix, report.skills + report.messages),
      ("total", entry.total.value, report.total),
    ]
    let detail = rows.map { name, ours, theirs in
      "\(name) \(TokenFormat.tokens(ours)) against \(TokenFormat.tokens(theirs)) "
        + "(\(TokenFormat.signedPercent(share(ours, of: theirs))))"
    }
    let totals = share(entry.total.value, of: report.total)
    return ValidationCheck(
      name: "bands against the harness's own report",
      passed: abs(totals) <= 0.25,
      detail: "at \(RequestNumber.name(at)): " + detail.joined(separator: ", ")
    )
  }

  /// How far one number is from another, as a share of the other.
  private static func share(_ ours: Int, of theirs: Int) -> Double {
    guard theirs > 0 else { return 0 }
    return Double(ours - theirs) / Double(theirs)
  }
}
