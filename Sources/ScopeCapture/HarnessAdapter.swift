public import Foundation
public import ScopeCore

/// What one session looks like after capture: the recording, and what a use
/// judge needs to score it. The adapter measures nothing itself, so the
/// judge and the analyzers stay out of the capture path.
public struct CapturedSession: Sendable {
  /// The cap the adapter applied when it shingled segments, so a judge can
  /// report the method it was actually given.
  public static let segmentShingleCap = LaneBuilder.shingleCap

  public let recording: Recording
  public let judgeInputs: [LaneID: JudgeInput]
  /// The estimator fit each lane accumulated, so `calibrate` can pool them.
  public let calibrations: [LaneID: EstimatorCalibration]

  public init(
    recording: Recording,
    judgeInputs: [LaneID: JudgeInput],
    calibrations: [LaneID: EstimatorCalibration] = [:]
  ) {
    self.recording = recording
    self.judgeInputs = judgeInputs
    self.calibrations = calibrations
  }

  /// Feeds a fresh judge of the given kind with each lane and collects what
  /// it found. The judge is fed, never handed the session.
  public func references<Judge: UseJudge>(
    by make: () -> Judge
  ) -> [LaneID: ReferenceReport] {
    var reports: [LaneID: ReferenceReport] = [:]
    for (lane, input) in judgeInputs {
      var judge = make()
      judge.add(input)
      reports[lane] = judge.report()
    }
    return reports
  }
}

/// A session the adapter knows about, before anything is parsed.
public struct SessionRef: Sendable, Hashable, Identifiable {
  public let id: String
  public let project: String
  public let url: URL
  public let title: String?
  public let lastActivity: Date
  public let byteSize: Int
  /// Written to in the last few minutes.
  public let isLive: Bool

  public init(
    id: String,
    project: String,
    url: URL,
    title: String?,
    lastActivity: Date,
    byteSize: Int,
    isLive: Bool
  ) {
    self.id = id
    self.project = project
    self.url = url
    self.title = title
    self.lastActivity = lastActivity
    self.byteSize = byteSize
    self.isLive = isLive
  }
}

public protocol HarnessAdapter: Sendable {
  var name: String { get }
  /// Sessions this harness has on the machine, newest first. Anything a
  /// previous scan learned about a file that has not changed is reused, which
  /// is what keeps a rescan to a directory listing.
  func sessions(reusing known: [String: SessionRef]) throws -> [SessionRef]
  /// Reads one session into a recording.
  func capture(_ session: SessionRef, includeSubagents: Bool) throws -> CapturedSession
}

extension HarnessAdapter {
  public func sessions() throws -> [SessionRef] { try sessions(reusing: [:]) }
}

public enum CaptureError: Error, CustomStringConvertible {
  case noSuchSession(String)
  case ambiguousSession(String, [String])

  public var description: String {
    switch self {
    case .noSuchSession(let id):
      "no session matches \(id)"
    case .ambiguousSession(let id, let matches):
      "\(matches.count) sessions match \(id): "
        + matches.prefix(4).map { String($0.prefix(12)) }.joined(separator: ", ")
    }
  }
}
