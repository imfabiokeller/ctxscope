/// Composition per request: tokens per band, fill, prefix overhead.
///
/// Incremental: segments are turned into birth and death events once, then
/// one sweep over the requests keeps running band sums. Cost is linear in
/// segments plus requests, never quadratic, which is what a 1M-token window
/// needs.

public struct RequestTally: Sendable, Codable, Hashable {
  public let request: Int
  public let total: Tokens
  /// Tokens per band, indexed like `BandRegistry.ordered`. The sum is the
  /// measured request total, but a band on its own is only as good as the
  /// segments in it.
  public let byBand: [Tokens]
  public let segmentCount: Int
  public let fill: Double
  /// Share of the request the prefix took, with the grade of the prefix.
  public let prefixShare: GradedShare
  public let zone: LengthZone
}

public struct Tally: Sendable, Codable {
  public let perRequest: [RequestTally]
  public let window: WindowEstimate
}

public enum TallyAnalyzer {
  public static func run(_ lane: Lane) -> Tally {
    let bandCount = BandRegistry.ordered.count
    let requestCount = lane.snapshots.count
    guard requestCount > 0 else { return Tally(perRequest: [], window: lane.window) }

    var births = [[Segment]](repeating: [], count: requestCount)
    var deaths = [[Segment]](repeating: [], count: requestCount)
    for segment in lane.segments {
      guard segment.born >= 0, segment.born < requestCount else { continue }
      births[segment.born].append(segment)
      if let died = segment.died, died >= 0, died < requestCount {
        deaths[died].append(segment)
      }
    }

    var running = [Int](repeating: 0, count: bandCount)
    var worst = [Grade](repeating: .measured, count: bandCount)
    var liveCount = 0
    var result: [RequestTally] = []
    result.reserveCapacity(requestCount)

    for request in 0..<requestCount {
      for segment in deaths[request] {
        running[BandRegistry.position(of: segment.band)] -= segment.tokens.value
        liveCount -= 1
      }
      for segment in births[request] {
        let slot = BandRegistry.position(of: segment.band)
        running[slot] += segment.tokens.value
        worst[slot] = max(worst[slot], segment.tokens.grade)
        liveCount += 1
      }
      let measured = lane.snapshots[request].usage.promptTotal
      let prefix = BandRegistry.bands(in: .prefix)
        .reduce(0) { $0 + running[BandRegistry.position(of: $1)] }
      let fill = lane.window.fill(measured)
      result.append(
        RequestTally(
          request: request,
          total: Tokens(measured, .measured),
          byBand: zip(running, worst).map(Tokens.init),
          segmentCount: liveCount,
          fill: fill,
          prefixShare: GradedShare(
            value: measured > 0 ? Double(prefix) / Double(measured) : 0,
            grade: BandRegistry.bands(in: .prefix)
              .map { worst[BandRegistry.position(of: $0)] }.max() ?? .estimated),
          // Zones are absolute lengths and per model, so the scale is the one
          // of the request being tallied: a lane that switched model half way
          // through used to keep the first scale to the end.
          zone: lane.zones(at: request).zone(ofLength: measured)
        )
      )
    }
    return Tally(perRequest: result, window: lane.window)
  }
}

extension RequestTally {
  /// Tokens per kind, indexed like `Kind.allCases`: what a stacked column and
  /// the legend show. Summed from the bands when asked, which is thirteen
  /// additions, so every column of a long lane can ask on every frame.
  public var byKind: [Tokens] {
    Kind.allCases.map { tokens(of: $0) }
  }

  public func tokens(of kind: Kind) -> Tokens {
    BandRegistry.bands(of: kind).reduce(Tokens.zero) {
      $0 + byBand[BandRegistry.position(of: $1)]
    }
  }

  /// Tokens no kind holds. The kinds and this add up to `total`.
  public var untyped: Tokens {
    byBand[BandRegistry.position(of: .unattr)]
  }

  /// What is sent with every request: system, tools and memory.
  public var prefixTokens: Tokens {
    BandRegistry.bands(in: .prefix).reduce(Tokens.zero) {
      $0 + byBand[BandRegistry.position(of: $1)]
    }
  }
}
