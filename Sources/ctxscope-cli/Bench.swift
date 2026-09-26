import Foundation
import ScopeCapture
import ScopeCore

/// Times capture and every analyzer at scale. A 1M-token window is a
/// first-class case, and capture is what actually costs seconds on
/// a real session, so both are measured here.
enum BenchCommand {
  static func run(_ arguments: Arguments) throws {
    try benchAnalysis(arguments)
    Console.out("")
    try benchCapture(arguments)
  }

  private static func benchAnalysis(_ arguments: Arguments) throws {
    var options = SyntheticRecording.Options.millionTokenWindow
    if let requests = arguments.integer("requests") { options.requests = requests }
    if let window = arguments.integer("window") { options.window = window }
    if let seed = arguments.integer("seed") { options.seed = UInt64(seed) }

    let built = Timing.of { SyntheticRecording.make(options) }
    guard let lane = built.value.mainLane else {
      throw CLIError.usage("the synthetic recording has no lane")
    }
    let peak = lane.snapshots.map(\.usage.promptTotal).max() ?? 0
    Console.out(
      "analysis: \(lane.snapshots.count) requests, \(lane.segments.count) segments, "
        + "peak \(TokenFormat.tokens(peak)) of \(lane.window.label)")
    Console.out("  build              \(Timing.text(built.seconds))")

    let input = SyntheticJudge.input(for: lane)
    let judged = Timing.of { () -> ReferenceReport in
      var judge = LexicalJudge(segmentShingleCap: CapturedSession.segmentShingleCap)
      judge.add(input)
      return judge.report()
    }
    let references = judged.value
    let steps: [(String, Timing.Sample<Any>)] = [
      ("lexical judge", Timing.erase(judged)),
      ("tally", Timing.erase(Timing.of { TallyAnalyzer.run(lane) })),
      ("cache", Timing.erase(Timing.of { CacheAnalyzer.run(lane) })),
      ("segment cache", Timing.erase(Timing.of { SegmentCacheAnalyzer.run(lane) })),
      (
        "carry cost",
        Timing.erase(Timing.of { CarryCostAnalyzer.run(lane, references: references) })
      ),
      ("duplication", Timing.erase(Timing.of { DuplicationAnalyzer.run(lane) })),
      ("compaction", Timing.erase(Timing.of { CompactionAnalyzer.run(lane) })),
      (
        "reused ratio",
        Timing.erase(
          Timing.of {
            ReferenceAnalyzer.run(lane, references: references, at: lane.snapshots.count - 1)
          })
      ),
      ("validation", Timing.erase(Timing.of { Validator.run(lane) })),
    ]
    var total = built.seconds
    for (name, sample) in steps {
      Console.out("  " + TokenFormat.padRight(name, to: 19) + Timing.text(sample.seconds))
      total += sample.seconds
    }
    Console.out("  " + TokenFormat.padRight("total", to: 19) + Timing.text(total))
    if total > 2 {
      Console.error("over the two second bar for this scale")
      exit(1)
    }
  }

  /// Capture on a synthetic transcript of realistic size, cold and then
  /// incremental, which is the number that decides whether following a live
  /// session is affordable.
  private static func benchCapture(_ arguments: Arguments) throws {
    var shape = SyntheticTranscript.realistic
    if let requests = arguments.integer("capture-requests") { shape.requests = requests }
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "ctxscope-bench-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "bench.jsonl")

    let lines = try SyntheticTranscript.write(shape, to: url)
    let bytes =
      ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size]
        as? Int) ?? 0
    Console.out(
      "capture: \(lines) lines, \(TokenFormat.bytes(bytes)) of synthetic transcript")

    let reference = SessionRef(
      id: "bench", project: "bench", url: url, title: nil, lastActivity: Date(),
      byteSize: bytes, isLive: false)

    let cold = Timing.of { () -> Int in
      var capture = SessionCapture(session: reference, includeSubagents: false, window: nil)
      guard (try? capture.refresh()) != nil else { return 0 }
      return capture.finish().recording.mainLane?.snapshots.count ?? 0
    }
    Console.out(
      "  cold read          \(Timing.text(cold.seconds)) for \(cold.value) requests")

    // Now the case that matters for following a session: read it once, append
    // a little, read again.
    var capture = SessionCapture(session: reference, includeSubagents: false, window: nil)
    try capture.refresh()
    let tail = try String(contentsOf: url, encoding: .utf8)
      .split(separator: "\n").suffix(12).joined(separator: "\n")
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((tail + "\n").utf8))
    try handle.close()

    let warm = Timing.of { () -> SessionCapture.Refresh in
      (try? capture.refresh()) ?? SessionCapture.Refresh()
    }
    Console.out(
      "  refresh after 12 new lines \(Timing.text(warm.seconds)) "
        + "for \(warm.value.newLines) lines")
    let ratio = cold.seconds > 0 ? warm.seconds / cold.seconds : 0
    Console.out("  refresh costs \(TokenFormat.finePercent(ratio)) of a cold read")
  }
}

/// One place that times things and prints the number.
enum Timing {
  struct Sample<Value> {
    let value: Value
    let seconds: Double
  }

  static func of<Value>(_ body: () -> Value) -> Sample<Value> {
    let start = DispatchTime.now().uptimeNanoseconds
    let value = body()
    let end = DispatchTime.now().uptimeNanoseconds
    return Sample(value: value, seconds: Double(end - start) / 1_000_000_000)
  }

  static func erase<Value>(_ sample: Sample<Value>) -> Sample<Any> {
    Sample(value: sample.value, seconds: sample.seconds)
  }

  static func text(_ seconds: Double) -> String {
    seconds >= 1
      ? TokenFormat.ratio(seconds, places: 2) + " s"
      : TokenFormat.ratio(seconds * 1000, places: 1) + " ms"
  }
}
