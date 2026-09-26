import Foundation

/// A seeded synthetic recording, shaped like a real session: a prefix, then
/// prompts, responses and tool results, with a compaction and a cache bust.
/// It exists so scale can be tested without a real 1M-token session: the
/// analyzers must stay incremental, and this is what proves it.
public enum SyntheticRecording {
  public struct Options: Sendable {
    public var requests: Int
    public var window: Int
    public var compactAt: Int?
    /// A request where the prefix changed, so the whole cache is written
    /// again: a bust. Every synthetic session has one, because real sessions
    /// have them.
    public var bustAt: Int?
    public var subagentsAt: [Int]
    public var peakTokens: Int
    public var seed: UInt64

    public init(
      requests: Int = 64,
      window: Int = 200_000,
      compactAt: Int? = 44,
      bustAt: Int? = 30,
      subagentsAt: [Int] = [22, 51],
      peakTokens: Int = 162_000,
      seed: UInt64 = 11
    ) {
      self.requests = requests
      self.window = window
      self.compactAt = compactAt
      self.bustAt = bustAt
      self.subagentsAt = subagentsAt
      self.peakTokens = peakTokens
      self.seed = seed
    }

    /// A session with one request: the prefix and nothing else, which is what
    /// a window opened on a session that has just started shows.
    public static let oneRequest = Options(
      requests: 0, window: 200_000, compactAt: nil, bustAt: nil, subagentsAt: [],
      peakTokens: 52_000, seed: 3)

    /// The same with a second request, which is the first length that has a
    /// boundary between columns to draw.
    public static let twoRequests = Options(
      requests: 1, window: 200_000, compactAt: nil, bustAt: nil, subagentsAt: [],
      peakTokens: 64_000, seed: 3)

    /// A 1M-token window without compaction: nothing ever leaves, so carry
    /// cost grows quadratically and every analyzer has to stay linear.
    public static let millionTokenWindow = Options(
      requests: 360,
      window: 1_000_000,
      compactAt: nil,
      bustAt: 200,
      subagentsAt: [40, 120, 210, 300],
      peakTokens: 790_000,
      seed: 5
    )
  }

  public static func make(_ options: Options = Options()) -> Recording {
    var random = Random(seed: options.seed)
    var segments: [Segment] = []
    var next = 0

    // Reading the same file twice puts the same content in the context
    // twice. The duplication analyzer needs that to have anything to find.
    var contentHashes: [String: UInt64] = [:]

    func add(
      _ band: Band,
      _ label: String,
      _ tokens: Int,
      born: Int,
      died: Int? = nil,
      grade: Grade = .estimated
    ) {
      let hash = band == .read ? contentHashes[label, default: random.next()] : random.next()
      if band == .read { contentHashes[label] = hash }
      segments.append(
        Segment(
          id: SegmentID(next),
          band: band,
          label: label,
          tokens: Tokens(max(12, tokens), grade),
          characters: max(12, tokens) * 3,
          contentClass: band == .call ? .json : .prose,
          born: born,
          died: died,
          contentHash: hash,
          // What the model produced points at the request that produced it.
          // A tool result is not that: the model asked for it, the harness put
          // it in.
          originRequest: [.asst, .think, .call].contains(band) ? born : nil
        )
      )
      next += 1
    }

    for (band, label, tokens) in PrefixSplit.segments(total: 52_000) {
      add(band, label, tokens, born: 0, grade: .derived)
    }

    let files = [
      "Segment.swift", "Recording.swift", "TranscriptAdapter.swift", "BandRegistry.swift",
      "Estimator.swift", "SpectrumView.swift", "Package.swift", "README.md",
    ]
    var nextUser = 1
    for request in 1...max(1, options.requests) {
      if request == nextUser {
        add(
          .user, request == 1 ? "First prompt" : "Follow-up at \(RequestNumber.name(request))",
          random.logNormal(request == 1 ? 420 : 130, 0.7), born: request)
        nextUser = request + 4 + Int(random.next() % 5)
      }
      add(
        .think, "Thinking, \(RequestNumber.name(request))", random.logNormal(520, 0.6),
        born: request, died: nextUser, grade: .measured)
      add(
        .asst, "Assistant text, \(RequestNumber.name(request))", random.logNormal(190, 0.7),
        born: request)
      let kind = random.unit()
      let band: Band = kind < 0.45 ? .read : (kind < 0.75 ? .bash : .srch)
      let file = files[Int(random.next() % UInt64(files.count))]
      let label = band == .read ? file : (band == .bash ? "swift build" : "grep \(file)")
      add(.call, "\(band.rawValue) \(label)", random.logNormal(90, 0.45), born: request)
      let size = min(14000, random.logNormal(band == .read ? 2300 : 1400, 0.95))
      add(band, label, size, born: request)
      if options.subagentsAt.contains(request) {
        add(
          .agent, "Subagent return at \(RequestNumber.name(request))", random.logNormal(1900, 0.2),
          born: request)
      }
    }

    if let compactAt = options.compactAt, compactAt <= options.requests {
      for index in segments.indices
      where BandRegistry.family(of: segments[index].band) != .prefix
        && segments[index].born < compactAt
      {
        segments[index].died = min(segments[index].died ?? compactAt, compactAt)
      }
      add(.asst, "Compaction summary", 6400, born: compactAt, grade: .derived)
    }

    scaleToPeak(&segments, options: options)
    let lane = assemble(segments: segments, options: options)
    return Recording(
      sessionID: "synthetic-\(options.seed)",
      project: "synthetic",
      title: "Synthetic \(TokenFormat.tokens(options.window)) window",
      lanes: [lane]
    )
  }

  /// Stretches everything outside the prefix so the fullest request lands on
  /// the requested peak. Without it a 1M window would never fill.
  private static func scaleToPeak(_ segments: inout [Segment], options: Options) {
    let at = (options.compactAt.map { min($0 - 1, options.requests) } ?? options.requests)
    guard at > 0 else { return }
    var fixed = 0
    var variable = 0
    for segment in segments where segment.isLive(at: at) {
      if BandRegistry.family(of: segment.band) == .prefix {
        fixed += segment.tokens.value
      } else {
        variable += segment.tokens.value
      }
    }
    guard variable > 0 else { return }
    let scale = Double(options.peakTokens - fixed) / Double(variable)
    guard scale > 0 else { return }
    for index in segments.indices
    where BandRegistry.family(of: segments[index].band) != .prefix {
      let scaled = max(12, Int(Double(segments[index].tokens.value) * scale))
      segments[index].tokens = Tokens(scaled, segments[index].tokens.grade)
    }
  }

  /// Builds the snapshots from the segments, so the request totals are exact
  /// by construction, the same invariant the real adapter has to hold.
  private static func assemble(segments: [Segment], options: Options) -> Lane {
    let count = options.requests + 1
    var totals = [Int](repeating: 0, count: count)
    var births = [Int](repeating: 0, count: count)
    for segment in segments {
      let died = min(segment.died ?? count, count)
      guard segment.born < count else { continue }
      births[segment.born] += segment.tokens.value
      for request in segment.born..<died { totals[request] += segment.tokens.value }
    }

    var snapshots: [Snapshot] = []
    for request in 0..<count {
      let total = totals[request]
      // What enters is written. A compaction rewrites everything after the
      // prefix, because the conversation behind it changed.
      var written = births[request]
      if request == 0 {
        written = total
      } else if request == options.compactAt {
        written = segments.filter {
          $0.isLive(at: request) && BandRegistry.family(of: $0.band) != .prefix
        }.reduce(0) { $0 + $1.tokens.value }
      } else if request == options.bustAt {
        // The prefix changed, so nothing matches and everything is written.
        written = total
      }
      written = min(written, total)
      let read = total - written
      snapshots.append(
        Snapshot(
          index: request,
          requestID: "synthetic-\(request)",
          timestamp: Double(request) * 12,
          model: "synthetic",
          usage: RequestUsage(
            inputTokens: 0,
            cacheReadTokens: read,
            cacheCreationTokens: written,
            outputTokens: births[min(request + 1, count - 1)],
            thinkingTokens: 0,
            ephemeral1hTokens: written
          ),
          residualTokens: 0,
          appendedTokens: births[request]
        )
      )
    }

    var compactions: [CompactionEvent] = []
    if let at = options.compactAt, at < count {
      compactions.append(
        CompactionEvent(
          atRequest: at,
          trigger: "synthetic",
          preTokens: totals[at - 1],
          postTokens: totals[at],
          droppedTokens: max(0, totals[at - 1] - totals[at])
        )
      )
    }

    return Lane(
      id: .main,
      window: WindowEstimate.given(options.window),
      segments: segments,
      snapshots: snapshots,
      compactions: compactions,
      // Every user block of the synthetic lane is a prompt somebody typed.
      prompts: segments.filter { $0.band == .user }.map(\.id)
    )
  }

  /// splitmix64, so a seed reproduces a recording exactly on any machine.
  public struct Random {
    private var state: UInt64

    public init(seed: UInt64) {
      state = seed &* 0x9e37_79b9_7f4a_7c15
    }

    public mutating func next() -> UInt64 {
      state &+= 0x9e37_79b9_7f4a_7c15
      var value = state
      value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
      value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
      return value ^ (value >> 31)
    }

    public mutating func unit() -> Double {
      Double(next() >> 11) / Double(1 << 53)
    }

    /// Box-Muller, then exponentiated: segment sizes spread the way real
    /// ones do, a few large among many small.
    public mutating func logNormal(_ median: Double, _ sigma: Double) -> Int {
      let u1 = max(1e-9, unit())
      let u2 = unit()
      let normal = (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
      return Int(median * exp(sigma * normal))
    }
  }
}
