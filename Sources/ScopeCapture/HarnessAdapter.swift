public import Foundation
public import ScopeCore

public struct CapturedSession: Sendable {
  public static let segmentShingleCap = LaneBuilder.shingleCap

  public let recording: Recording
  public let judgeInputs: [LaneID: JudgeInput]
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

public struct SessionRef: Sendable, Hashable, Identifiable {
  public let id: String
  public let project: String
  public let url: URL
  public let title: String?
  public let lastActivity: Date
  public let byteSize: Int
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
  func sessions(reusing known: [String: SessionRef]) throws -> [SessionRef]
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
