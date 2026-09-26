public import Foundation

/// The two shapes a recording leaves in, JSON and CSV. One home, so the CLI and
/// the window cannot disagree about what an export is.
public enum ExportFormat: String, Sendable, CaseIterable, Identifiable {
  case json
  case csv

  public var id: String { rawValue }
  public var fileExtension: String { rawValue }
}

/// Everything a JSON export carries.
///
/// Requests are numbered from one here, the way the window and the command
/// line show them, so a row of an export and a request a person read off the
/// screen are the same request. Inside a recording they are indices from zero,
/// because that is what they index.
public struct ExportPayload: Encodable, Sendable {
  /// Says out loud what every request number in this file counts from.
  public let requestNumbersFrom = 1
  public let sessionID: String
  public let project: String
  public let title: String?
  public let lane: Lane
  public let references: ReferenceReport

  public init(
    sessionID: String,
    project: String,
    title: String?,
    lane: Lane,
    references: ReferenceReport
  ) {
    self.sessionID = sessionID
    self.project = project
    self.title = title
    self.lane = lane
    self.references = references
  }
}

public enum Export {
  public static func text(_ payload: ExportPayload, format: ExportFormat) -> String {
    switch format {
    case .json:
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      guard let data = try? encoder.encode(numbered(payload)) else { return "" }
      return String(decoding: data, as: UTF8.self)
    case .csv:
      return csv(lane: payload.lane, references: payload.references)
    }
  }

  public static func data(_ payload: ExportPayload, format: ExportFormat) -> Data {
    Data(text(payload, format: format).utf8)
  }

  /// The same payload with every request numbered the way a person reads it.
  static func numbered(_ payload: ExportPayload) -> ExportPayload {
    let lane = payload.lane
    return ExportPayload(
      sessionID: payload.sessionID,
      project: payload.project,
      title: payload.title,
      lane: Lane(
        id: lane.id,
        agentType: lane.agentType,
        parentToolUseID: lane.parentToolUseID,
        window: lane.window,
        segments: lane.segments.map(numbered),
        snapshots: lane.snapshots.map(numbered),
        compactions: lane.compactions.map {
          CompactionEvent(
            atRequest: RequestNumber.of($0.atRequest), trigger: $0.trigger,
            preTokens: $0.preTokens, postTokens: $0.postTokens,
            droppedTokens: $0.droppedTokens)
        },
        events: lane.events.map {
          LaneEvent(
            request: RequestNumber.of($0.request), kind: $0.kind, tokens: $0.tokens,
            detail: $0.detail)
        },
        prompts: lane.prompts,
        calibration: lane.calibration,
        stats: lane.stats,
        prefixSource: lane.prefixSource,
        contextReport: lane.contextReport.map(numbered)
      ),
      references: ReferenceReport(
        method: payload.references.method,
        findings: payload.references.findings.map(numbered),
        cutoff: payload.references.cutoff
      )
    )
  }

  private static func numbered(_ segment: Segment) -> Segment {
    Segment(
      id: segment.id, band: segment.band, label: segment.label, tokens: segment.tokens,
      characters: segment.characters, contentClass: segment.contentClass,
      born: RequestNumber.of(segment.born), died: segment.died.map(RequestNumber.of),
      deathCause: segment.deathCause, contentHash: segment.contentHash,
      originRequest: segment.originRequest.map(RequestNumber.of))
  }

  private static func numbered(_ snapshot: Snapshot) -> Snapshot {
    Snapshot(
      index: RequestNumber.of(snapshot.index), requestID: snapshot.requestID,
      timestamp: snapshot.timestamp, model: snapshot.model, usage: snapshot.usage,
      parentRequest: snapshot.parentRequest.map(RequestNumber.of),
      residualTokens: snapshot.residualTokens, appendedTokens: snapshot.appendedTokens)
  }

  private static func numbered(_ finding: ReferenceFinding) -> ReferenceFinding {
    ReferenceFinding(
      segment: finding.segment, isAssessable: finding.isAssessable,
      referencedShare: finding.referencedShare,
      referenceRequests: finding.referenceRequests.map(RequestNumber.of),
      matchedCounts: finding.matchedCounts, assessedShingles: finding.assessedShingles)
  }

  private static func numbered(_ report: ContextReport) -> ContextReport {
    var copy = report
    copy.request = RequestNumber.of(report.request)
    return copy
  }

  /// One row per segment: the shape every later analysis starts from. The
  /// referenced share travels with it, because a segment without it cannot be
  /// read back into anything.
  public static func csv(lane: Lane, references: ReferenceReport) -> String {
    let findings = references.bySegment()
    var rows = [
      "segment,band,family,source,label,tokens,grade,characters,class,born,died,"
        + "death_cause,referenced_share,assessable,first_reference,content_hash"
    ]
    for segment in lane.segments {
      let finding = findings[segment.id]
      let assessable = finding?.isAssessable ?? segment.isAssessable
      rows.append(
        [
          String(segment.id.rawValue),
          segment.band.rawValue,
          segment.family.rawValue,
          segment.source.rawValue,
          escape(segment.label),
          String(segment.tokens.value),
          segment.tokens.grade.rawValue,
          String(segment.characters),
          segment.contentClass.rawValue,
          String(RequestNumber.of(segment.born)),
          segment.died.map { String(RequestNumber.of($0)) } ?? "",
          segment.deathCause?.rawValue ?? "",
          assessable ? TokenFormat.ratio(finding?.referencedShare ?? 0, places: 4) : "",
          assessable ? "yes" : "no",
          finding?.firstReference.map { String(RequestNumber.of($0)) } ?? "",
          String(segment.contentHash),
        ].joined(separator: ","))
    }
    return rows.joined(separator: "\n") + "\n"
  }

  private static func escape(_ text: String) -> String {
    guard text.contains(",") || text.contains("\"") || text.contains("\n") else { return text }
    return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }
}
