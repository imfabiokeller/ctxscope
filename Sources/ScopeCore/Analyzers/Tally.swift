public struct RequestTally: Sendable, Codable, Hashable {
  public let request: Int
  public let total: Tokens
  public let byBand: [Tokens]
  public let segmentCount: Int
  public let fill: Double
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
          zone: lane.zones(at: request).zone(ofLength: measured)
        )
      )
    }
    return Tally(perRequest: result, window: lane.window)
  }
}

extension RequestTally {
  public var byKind: [Tokens] {
    Kind.allCases.map { tokens(of: $0) }
  }

  public func tokens(of kind: Kind) -> Tokens {
    BandRegistry.bands(of: kind).reduce(Tokens.zero) {
      $0 + byBand[BandRegistry.position(of: $1)]
    }
  }

  public var untyped: Tokens {
    byBand[BandRegistry.position(of: .unattr)]
  }

  public var prefixTokens: Tokens {
    BandRegistry.bands(in: .prefix).reduce(Tokens.zero) {
      $0 + byBand[BandRegistry.position(of: $1)]
    }
  }
}
