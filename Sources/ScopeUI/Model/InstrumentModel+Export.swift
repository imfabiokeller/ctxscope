public import Foundation
public import ScopeCore

/// What the window can hand to a file: the recording and its metrics, through
/// the encoders the CLI uses, because there is only one answer.
extension InstrumentModel {
  /// The recording and its metrics, as JSON or CSV.
  public func export(_ format: ExportFormat) -> Data? {
    guard let analysis, let recording else { return nil }
    return Export.data(
      ExportPayload(
        sessionID: recording.sessionID,
        project: recording.project,
        title: recording.title,
        lane: analysis.lane,
        references: analysis.references
      ),
      format: format
    )
  }

  /// A file name that says which session and lane an export came from.
  public func exportName(_ format: ExportFormat) -> String {
    let session = recording?.sessionID.prefix(8) ?? "session"
    return "ctxscope-\(session)-\(lane.rawValue).\(format.fileExtension)"
  }
}
