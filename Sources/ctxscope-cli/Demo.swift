import Foundation

enum DemoCommand {
  static func run(_ arguments: Arguments) throws {
    guard let path = arguments.value("home") else {
      throw CLIError.usage("--home is required: the demo writes a home of its own")
    }
    let given = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    try refuseRealHome(given)
    try FileManager.default.createDirectory(at: given, withIntermediateDirectories: true)
    // Standardized the way `NSHomeDirectory()` reports a `CFFIXED_USER_HOME`
    // (`/private/tmp` as `/tmp`), so the window shows `~/code/api-client`.
    let home = URL(fileURLWithPath: (given.path as NSString).standardizingPath)

    let now = Date()
    var start: Date?
    if let text = arguments.value("start") {
      guard let date = ISO8601DateFormatter().date(from: text) else {
        throw CLIError.usage("--start takes an ISO 8601 time such as 2026-09-25T09:00:00Z")
      }
      start = date
    }
    var seconds: Double?
    if let text = arguments.value("live") {
      guard let value = Double(text), value >= 0 else {
        throw CLIError.usage("--live takes a number of seconds, not \"\(text)\"")
      }
      seconds = value
    }

    let session = DemoSession(home: home, day: start ?? now)
    let gaps = session.gaps
    let schedule: DemoSchedule
    if let seconds {
      schedule = .live(gaps: gaps, batch: DemoSession.liveBatch, now: now, seconds: seconds)
    } else if let start {
      schedule = .story(gaps: gaps, start: start)
    } else {
      schedule = .story(gaps: gaps, end: now.addingTimeInterval(-60))
    }
    let chunks = try session.chunks(schedule)

    Console.out("home        \(home.path)")
    Console.out("session     \(session.session)  \(DemoStory.title)")
    Console.out("project     \(session.project.cwd)")
    Console.out("transcript  \(session.transcript.path)")
    fflush(stdout)
    // A script waits for this line before it starts the app on the home.
    try session.write(chunks, liveFrom: seconds == nil ? nil : DemoSession.liveBatch) {
      Console.out(
        "live        requests 1 to \(DemoSession.liveBatch) written, the other "
          + "\(gaps.count - DemoSession.liveBatch) follow over \(Int(seconds ?? 0)) s")
      fflush(stdout)
    }
    Console.out("written     \(gaps.count) requests")
  }

  // Safety: the demo writes a `.claude` folder, never into the real home or anything holding it.
  private static func refuseRealHome(_ home: URL) throws {
    guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else {
      throw CLIError.usage("cannot tell where your home is, so the demo writes nothing")
    }
    let real = URL(fileURLWithPath: String(cString: directory)).resolvingSymlinksInPath().path
    let target = home.resolvingSymlinksInPath().path
    func holds(_ folder: String, _ path: String) -> Bool {
      path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }
    if holds(target, real) || holds(real + "/.claude", target) {
      throw CLIError.usage("\(home.path) is or holds your home; use a temporary folder")
    }
  }
}
