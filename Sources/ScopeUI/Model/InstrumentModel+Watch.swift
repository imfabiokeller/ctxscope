internal import Foundation

/// What is watched while a session is focused, and what a change to it means.
///
/// One session is shown, so one session is watched, and everything the
/// watcher says is about that session.
extension InstrumentModel {
  /// A write to the focused session is a refresh. Nothing else is watched, so
  /// nothing else can have changed.
  func somethingChanged() {
    refresh()
    // A subagent directory or a lane file that has only just appeared is
    // watched from here: a directory event says a file was added, not which.
    rearm()
  }

  /// A watched file was renamed or deleted. One scan says whether this
  /// machine still has the focused session: if it does, opening it again arms
  /// a watch on whatever is there now, and if it does not, the focus is let
  /// go and the window says so.
  func somethingVanished() {
    reloadSessions()
  }

  /// The files being watched, which is what says the bars move on their own.
  public var watchedPaths: [String] { watcher.watched }

  /// Watches the focused session and nothing else: its transcript, the
  /// directory its subagent lanes are written into, every lane file in there,
  /// and the project directory those sit in.
  ///
  /// One session is shown, so one session is watched. Watching the sixteen
  /// most recent project directories meant every session on the machine woke
  /// ctxscope to tell it about a session it would then ignore. A session the
  /// list does not know yet is found by a rescan, which the session menu and a
  /// `show` naming an unknown id ask for.
  ///
  /// The lane files are watched because a subagent is often where the
  /// interesting part of a session is: one can work for minutes while the main
  /// transcript says nothing, and a directory says nothing about a file inside
  /// it growing. The two directories above them are watched because that is
  /// where a `subagents` directory appears, and it appears while the main
  /// transcript is silent rather than with a write to it.
  func rearm() {
    guard let session = opened else { return watcher.watch([]) }
    let folder = session.url.deletingPathExtension()
    let lanes = folder.appending(path: "subagents")
    let urls =
      [session.url, session.url.deletingLastPathComponent(), folder, lanes]
      + laneFiles(in: lanes)
    watcher.watch(urls.filter { FileManager.default.fileExists(atPath: $0.path) })
  }

  private func laneFiles(in directory: URL) -> [URL] {
    let found = try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    return (found ?? []).filter { $0.pathExtension == "jsonl" }.sorted { $0.path < $1.path }
  }
}
