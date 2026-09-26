import Foundation
import ScopeCapture

/// Where the demo session goes in a home, and its files, request by request.
struct DemoSession {
  /// Requests written at once in a live run. The rest follow one at a time,
  /// starting with the one after the six minute pause.
  static let liveBatch = 41

  let home: URL
  let project: DemoProject
  let session: String

  /// The session in `home`, dated `day`.
  init(home: URL, day: Date) {
    self.home = home
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    project = DemoProject(
      home: home.path, cwd: home.path + "/code/api-client", today: formatter.string(from: day))
    var ids = DemoIDs(seed: DemoStory.title)
    session = ids.uuid()
  }

  var folder: URL {
    home.appending(path: ".claude/projects")
      .appending(path: ClaudeCodeAdapter.folderName(of: project.cwd))
  }

  var transcript: URL { folder.appending(path: "\(session).jsonl") }

  /// Bytes for one file, due at a moment. A transcript line is appended; a
  /// meta file is written whole.
  struct Chunk {
    let url: URL
    let data: Data
    let appends: Bool
    let due: Date
    /// The main lane request it belongs to.
    let request: Int
  }

  var gaps: [Double] { DemoStory.turns(project).map(\.gap) }

  /// Everything the session writes, in the order it is written.
  func chunks(_ schedule: DemoSchedule) throws -> [Chunk] {
    var main = DemoLane(session: session, cwd: project.cwd, agentID: nil, prefix: .main())
    let title = try JSONLines.line([
      "type": "custom-title", "customTitle": DemoStory.title, "sessionId": session,
    ])
    var chunks: [Chunk] = []
    for (index, turn) in DemoStory.turns(project).enumerated() {
      let times = schedule.times(of: index, waits: turn.calls.contains { $0.agent != nil })
      let (entries, spawned) = main.request(turn, at: times)
      for run in spawned {
        chunks += try subagent(run, at: times, request: index)
      }
      var lines = try entries.map(JSONLines.line)
      // The harness writes the title again as the file grows, so it stays
      // in the tail where it is looked for.
      if turn.inputs.contains(where: \.isPrompt) { lines.append(title) }
      chunks.append(
        Chunk(
          url: transcript, data: JSONLines.file(lines), appends: true,
          due: turn.calls.isEmpty ? times.response : times.results, request: index))
    }
    return chunks
  }

  /// A subagent run: its lane, and the meta file that links it to the call.
  private func subagent(_ run: DemoLane.Spawned, at times: DemoTimes, request: Int) throws
    -> [Chunk]
  {
    let agent = run.agent
    let folder = folder.appending(path: "\(session)/subagents")
    var lane = DemoLane(
      session: session, cwd: project.cwd, agentID: agent.id, prefix: .subagent(agent.type))
    var lines: [Data] = []
    for (position, turn) in agent.turns.enumerated() {
      var turn = turn
      if position == 0 { turn.inputs.insert(.task(agent.prompt), at: 0) }
      let (entries, _) = lane.request(turn, at: times.subagent(position, of: agent.turns.count))
      lines += try entries.map(JSONLines.line)
    }
    let meta: [String: Any] = [
      "agentType": agent.type, "description": run.description, "toolUseId": run.toolUseID,
      "spawnDepth": 1,
    ]
    return [
      Chunk(
        url: folder.appending(path: "agent-\(agent.id).jsonl"), data: JSONLines.file(lines),
        appends: true, due: times.response, request: request),
      Chunk(
        url: folder.appending(path: "agent-\(agent.id).meta.json"),
        data: try JSONLines.line(meta), appends: false, due: times.response, request: request),
    ]
  }

  /// Writes the chunks, waiting for each one's moment from `liveFrom` on.
  /// Before that, and in a run that is not live, everything is written at
  /// once.
  /// `batched` is called once the requests before `liveFrom` are on disk.
  func write(_ chunks: [Chunk], liveFrom: Int? = nil, batched: () -> Void = {}) throws {
    try? FileManager.default.removeItem(at: transcript)
    try? FileManager.default.removeItem(at: folder.appending(path: session))
    var waiting = liveFrom != nil
    for chunk in chunks {
      if let liveFrom, chunk.request >= liveFrom {
        if waiting { batched() }
        waiting = false
        Thread.sleep(until: chunk.due)
      }
      try FileManager.default.createDirectory(
        at: chunk.url.deletingLastPathComponent(), withIntermediateDirectories: true)
      guard chunk.appends, FileManager.default.fileExists(atPath: chunk.url.path) else {
        try chunk.data.write(to: chunk.url)
        continue
      }
      let handle = try FileHandle(forWritingTo: chunk.url)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: chunk.data)
    }
  }
}
