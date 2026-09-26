public import Foundation
public import ScopeCapture
public import ScopeCore

public protocol SessionFeed: Sendable {
  func sessions(reusing known: [String: SessionRef]) throws -> [SessionRef]
  // Can take seconds: implementations check for cancellation between batches.
  func open(_ session: SessionRef, hints: ModelWindowHints) throws -> any OpenSession
}

public protocol OpenSession: AnyObject {
  var session: SessionRef { get }
  var captured: CapturedSession { get }
  @discardableResult func refresh() throws -> Bool
  func references(of lane: LaneID) -> ReferenceReport
  func content(of segment: SegmentID, lane: LaneID) -> SegmentContent?
  func details(of segments: [SegmentID], lane: LaneID) -> [SegmentID: BlockDetail]
}

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
