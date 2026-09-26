public import Foundation
public import ScopeCore

extension InstrumentModel {
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

  public func exportName(_ format: ExportFormat) -> String {
    let session = recording?.sessionID.prefix(8) ?? "session"
    return "ctxscope-\(session)-\(lane.rawValue).\(format.fileExtension)"
  }
}
