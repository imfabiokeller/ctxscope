import Foundation
import ScopeCapture
import ScopeCore

/// The recording and its metrics, as JSON or CSV. Labels can name files the
/// session touched, so the output goes where the caller asks and nowhere
/// else. The encoders themselves live in ScopeCore, because the window exports
/// the same thing.
enum ExportCommand {
  static func run(_ arguments: Arguments) throws {
    let (session, captured) = try Loader.capture(arguments)
    let lane = try Loader.lane(captured, arguments)
    guard let format = ExportFormat(rawValue: arguments.value("format") ?? "json") else {
      throw CLIError.usage("format must be json or csv")
    }
    let text = Export.text(
      ExportPayload(
        sessionID: session.id,
        project: session.project,
        title: session.title,
        lane: lane,
        references: Loader.references(captured, lane)
      ),
      format: format
    )

    if let path = arguments.value("out") {
      try text.write(toFile: path, atomically: true, encoding: .utf8)
      Console.error("wrote \(path)")
    } else {
      Console.out(text)
    }
  }
}
