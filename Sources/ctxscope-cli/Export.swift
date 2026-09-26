import Foundation
import ScopeCapture
import ScopeCore

// Privacy: labels can name files the session touched, so output goes only where asked.
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
