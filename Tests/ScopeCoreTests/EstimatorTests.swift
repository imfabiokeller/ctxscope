import Testing

@testable import ScopeCore

@Suite("Estimator calibration")
struct EstimatorTests {
  private func sample(
    prose: Int = 0,
    code: Int = 0,
    json: Int = 0,
    blocks: Int = 1,
    prosePerToken: Double = 3,
    codePerToken: Double = 4,
    jsonPerToken: Double = 2,
    framing: Double = 100
  ) -> EstimatorSample {
    let tokens =
      Double(prose) / prosePerToken + Double(code) / codePerToken + Double(json) / jsonPerToken
      + framing + EstimatorRates.tokensPerBlock * Double(blocks)
    return EstimatorSample(
      characters: [.prose: prose, .code: code, .json: json],
      blocks: blocks,
      tokens: Int(tokens.rounded())
    )
  }

  @Test("with no samples the prior stands")
  func priorUntilFitted() {
    let calibration = EstimatorCalibration()
    #expect(calibration.sampleCount == 0)
    #expect(calibration.rates() == EstimatorRates.prior)
  }

  @Test("the fit recovers rates it was built from")
  func recoversRates() {
    var calibration = EstimatorCalibration()
    for size in stride(from: 400, through: 20_000, by: 200) {
      calibration.observe(sample(prose: size))
      calibration.observe(sample(code: size, blocks: 2))
      calibration.observe(sample(json: size, blocks: 3))
      calibration.observe(sample(prose: size / 2, code: size / 3, json: size / 4, blocks: 4))
    }
    let rates = calibration.rates()
    #expect(abs(rates.charactersPerToken(.prose) - 3) < 0.35)
    #expect(abs(rates.charactersPerToken(.code) - 4) < 0.5)
    #expect(abs(rates.charactersPerToken(.json) - 2) < 0.3)
    #expect(rates.samples > 100)
  }

  @Test("a handful of samples cannot move the prior far")
  func ridgeHoldsTheLine() {
    var calibration = EstimatorCalibration()
    // Three absurd deltas: one character claiming ten thousand tokens.
    for _ in 0..<3 {
      calibration.observe(
        EstimatorSample(characters: [.prose: 1], blocks: 1, tokens: 10_000))
    }
    let rates = calibration.rates()
    let prior = EstimatorRates.prior.charactersPerToken(.prose)
    #expect(rates.charactersPerToken(.prose) >= prior / 3)
    #expect(rates.charactersPerToken(.prose) <= prior * 3)
  }

  @Test("no fit can produce a negative or infinite rate")
  func staysSane() {
    var calibration = EstimatorCalibration()
    for tokens in [1, 2, 3, 5, 8, 13, 21] {
      calibration.observe(
        EstimatorSample(characters: [.prose: 100_000], blocks: 1, tokens: tokens))
    }
    let rates = calibration.rates()
    for contentClass in ContentClass.allCases {
      #expect(rates.rate(for: contentClass) > 0)
      #expect(rates.rate(for: contentClass).isFinite)
    }
    #expect(rates.tokensPerRequest >= 0)
    #expect(rates.tokensPerRequest.isFinite)
  }

  @Test("pooling two fits is the same as fitting the pool")
  func mergeIsAdditive() {
    var first = EstimatorCalibration()
    var second = EstimatorCalibration()
    var both = EstimatorCalibration()
    for size in stride(from: 500, through: 8000, by: 250) {
      let one = sample(prose: size)
      let two = sample(code: size, blocks: 2)
      first.observe(one)
      second.observe(two)
      both.observe(one)
      both.observe(two)
    }
    first.merge(second)
    #expect(first.sampleCount == both.sampleCount)
    #expect(
      abs(
        first.rates().charactersPerToken(.prose)
          - both.rates().charactersPerToken(.prose)) < 0.001)
  }

  @Test("framing is charged per request, not per block")
  func framingIsPerRequest() {
    let rates = EstimatorRates.prior
    let estimate = rates.estimate(characters: 50, contentClass: .prose)
    #expect(estimate < 30)
    #expect(rates.tokensPerRequest > 50)
  }
}
