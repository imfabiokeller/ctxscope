import Testing

@testable import ScopeCore

@Suite("BandRegistry")
struct BandRegistryTests {
  @Test("every band has a family, a source and a label")
  func complete() {
    for band in BandRegistry.ordered {
      #expect(!BandRegistry.label(of: band).isEmpty)
      #expect(Family.allCases.contains(BandRegistry.family(of: band)))
      #expect(Source.allCases.contains(BandRegistry.source(of: band)))
    }
    #expect(BandRegistry.ordered.count == Band.allCases.count)
  }

  @Test("bands are ordered by prompt position, prefix first")
  func order() {
    #expect(BandRegistry.position(of: .sys) == 0)
    #expect(BandRegistry.position(of: .agent) == BandRegistry.ordered.count - 1)
    #expect(BandRegistry.bands(in: .prefix) == [.sys, .tools, .mcp, .mem])
  }

  @Test("unattributed content stands outside the prefix and outside the harness")
  func unattributed() {
    #expect(BandRegistry.family(of: .unattr) == .unattributed)
    #expect(BandRegistry.source(of: .unattr) == .unknown)
    #expect(!BandRegistry.bands(in: .prefix).contains(.unattr))
    #expect(BandRegistry.bands(in: .unattributed) == [.unattr])
    #expect(!BandRegistry.isAssessable(.unattr))
  }

  @Test("rules and schemas are not assessable")
  func assessable() {
    #expect(!BandRegistry.isAssessable(.sys))
    #expect(!BandRegistry.isAssessable(.mem))
    #expect(!BandRegistry.isAssessable(.tools))
    #expect(BandRegistry.isAssessable(.read))
  }
}

@Suite("Kinds")
struct KindTests {
  @Test("every band but the unattributed one has exactly one kind")
  func mapping() {
    #expect(BandRegistry.kind(of: .sys) == .system)
    #expect(BandRegistry.bands(of: .tools) == [.tools, .mcp])
    #expect(BandRegistry.bands(of: .memory) == [.mem])
    #expect(BandRegistry.bands(of: .you) == [.user])
    #expect(BandRegistry.bands(of: .agent) == [.asst, .think, .call])
    #expect(BandRegistry.bands(of: .results) == [.read, .bash, .srch, .agent])
    #expect(BandRegistry.kind(of: .unattr) == nil)
    let covered = Kind.allCases.flatMap { BandRegistry.bands(of: $0) }
    #expect(covered.count == Band.allCases.count - 1)
  }

  @Test("kinds are in reading order, and the prefix is system, tools and memory")
  func order() {
    #expect(Kind.allCases == [.system, .tools, .memory, .you, .agent, .results])
    let prefix = BandRegistry.bands(in: .prefix).compactMap { BandRegistry.kind(of: $0) }
    #expect(Set(prefix) == [.system, .tools, .memory])
  }

  @Test("the kinds and the untyped remainder add up to the measured total")
  func tallyByKind() {
    let lane = SyntheticRecording.make().mainLane!
    for entry in TallyAnalyzer.run(lane).perRequest {
      let kinds = entry.byKind.reduce(0) { $0 + $1.value }
      #expect(kinds + entry.untyped.value == entry.total.value)
      let prefix = [Kind.system, .tools, .memory].reduce(0) {
        $0 + entry.tokens(of: $1).value
      }
      #expect(entry.prefixTokens.value == prefix)
    }
  }
}
