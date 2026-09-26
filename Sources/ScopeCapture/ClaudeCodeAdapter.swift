public import Foundation
internal import ScopeCore

// `~/.claude/projects` is input only: never write, move or lock anything under it.
public struct ClaudeCodeAdapter: HarnessAdapter {
  public let name = "claude-code"
  public let root: URL
  // A transcript never says its window; when nil, the lane infers a lower bound.
  public let contextWindow: Int?

  public init(root: URL? = nil, contextWindow: Int? = nil) {
    self.root =
      root
      ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".claude/projects")
    self.contextWindow = contextWindow
  }

  public static func folderName(of path: String) -> String {
    String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
  }

  private var window: WindowEstimate? {
    contextWindow.map(WindowEstimate.given)
  }

  public func sessions(reusing known: [String: SessionRef] = [:]) throws -> [SessionRef] {
    try SessionDiscovery(root: root).sessions(reusing: known)
  }

  public func session(matching id: String) throws -> SessionRef {
    let all = try sessions()
    if let exact = all.first(where: { $0.id == id }) { return exact }
    let prefixed = all.filter { $0.id.hasPrefix(id) }
    guard let first = prefixed.first else { throw CaptureError.noSuchSession(id) }
    guard prefixed.count == 1 else {
      throw CaptureError.ambiguousSession(id, prefixed.map(\.id))
    }
    return first
  }

  public func capture(_ session: SessionRef, includeSubagents: Bool = true) throws
    -> CapturedSession
  {
    var capture = SessionCapture(
      session: session, includeSubagents: includeSubagents, window: window)
    try capture.refresh()
    return capture.finish()
  }

  public func open(_ session: SessionRef, includeSubagents: Bool = true) -> SessionCapture {
    SessionCapture(session: session, includeSubagents: includeSubagents, window: window)
  }

  static func entries(at url: URL) throws -> [TranscriptEntry] {
    let result = try JSONLReader(url: url).read()
    return result.entries.map(TranscriptEntry.init)
  }

  struct SubagentRef: Sendable {
    let lane: LaneID
    let url: URL
    let agentType: String?
    let toolUseID: String?
  }

  static func subagents(of session: SessionRef) throws -> [SubagentRef] {
    let directory = session.url.deletingPathExtension().appending(path: "subagents")
    let manager = FileManager.default
    guard manager.fileExists(atPath: directory.path) else { return [] }
    let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    return
      files
      .filter { $0.pathExtension == "jsonl" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .map { url in
        let stem = url.deletingPathExtension().lastPathComponent
        let meta = url.deletingLastPathComponent().appending(path: "\(stem).meta.json")
        let metadata = Self.readMeta(at: meta)
        return SubagentRef(
          lane: LaneID(url.deletingPathExtension().lastPathComponent),
          url: url,
          agentType: metadata?["agentType"]?.string,
          toolUseID: metadata?["toolUseId"]?.string
        )
      }
  }

  private static func readMeta(at url: URL) -> JSONValue? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONValue(parsing: data)
  }
}
