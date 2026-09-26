public import Foundation
public import ScopeCapture
public import ScopeCore

/// Where the instrument gets its sessions.
///
/// A protocol rather than the adapter itself, so the views can be driven by a
/// fixture or by a synthetic recording without a transcript anywhere near
/// them, which is what the snapshot renderer does.
public protocol SessionFeed: Sendable {
  /// Sessions on the machine, newest first. Anything a previous scan learned
  /// about a file that has not changed is reused, which is what keeps a
  /// rescan to a directory listing rather than a tail read of every file.
  func sessions(reusing known: [String: SessionRef]) throws -> [SessionRef]
  /// Opens one session and keeps it open, so following it costs its new lines.
  ///
  /// It may take seconds, so it checks for cancellation between batches: a
  /// user who picks another session should not wait for the one they left.
  func open(_ session: SessionRef, hints: ModelWindowHints) throws -> any OpenSession
}

/// One session held open: the recording as it stands, and everything measured
/// about it.
///
/// The UI never parses anything. It asks this for a recording, for the text of
/// a segment, and for what a judge found, and all three come from below.
public protocol OpenSession: AnyObject {
  var session: SessionRef { get }
  var captured: CapturedSession { get }
  /// Reads whatever has arrived since the last call. True when anything did.
  @discardableResult func refresh() throws -> Bool
  func references(of lane: LaneID) -> ReferenceReport
  func content(of segment: SegmentID, lane: LaneID) -> SegmentContent?
  /// What each of these segments of a lane is about, for the ones that say.
  func details(of segments: [SegmentID], lane: LaneID) -> [SegmentID: BlockDetail]
}

/// The feed over the Claude Code transcripts on this machine.
public struct TranscriptFeed: SessionFeed {
  private let adapter: ClaudeCodeAdapter

  public init(root: URL? = nil, contextWindow: Int? = nil) {
    adapter = ClaudeCodeAdapter(root: root, contextWindow: contextWindow)
  }

  public func sessions(reusing known: [String: SessionRef]) throws -> [SessionRef] {
    try adapter.sessions(reusing: known)
  }

  public func open(_ session: SessionRef, hints: ModelWindowHints) throws -> any OpenSession {
    let open = TranscriptSession(
      capture: adapter.open(session, includeSubagents: true), session: session)
    open.windowHints = hints
    try open.refresh()
    return open
  }
}
