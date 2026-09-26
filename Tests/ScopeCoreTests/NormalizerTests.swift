import Testing

@testable import ScopeCore

@Suite("Normalizer")
struct NormalizerTests {
  @Test("parts sum to the total exactly")
  func partsSumExactly() {
    for total in [1, 7, 100, 999, 123_457] {
      for count in [1, 2, 3, 7, 13] {
        let weights = (0..<count).map { Double($0 + 1) * 1.7 }
        let parts = Normalizer.allocate(total: total, weights: weights)
        #expect(parts.reduce(0, +) == total)
        #expect(parts.count == count)
      }
    }
  }

  @Test("every part gets at least one token when the total allows it")
  func floorIsHonoured() {
    let parts = Normalizer.allocate(total: 100, weights: [1000, 1, 1, 1])
    #expect(parts.allSatisfy { $0 >= 1 })
    #expect(parts.reduce(0, +) == 100)
  }

  @Test("a total smaller than the count still sums exactly")
  func tinyTotal() {
    let parts = Normalizer.allocate(total: 3, weights: [5, 5, 5, 5, 5, 5])
    #expect(parts.reduce(0, +) == 3)
  }

  @Test("zero weights split evenly")
  func zeroWeights() {
    let parts = Normalizer.allocate(total: 10, weights: [0, 0, 0])
    #expect(parts.reduce(0, +) == 10)
    #expect(parts.max()! - parts.min()! <= 1)
  }

  @Test("a zero total gives zero parts")
  func zeroTotal() {
    #expect(Normalizer.allocate(total: 0, weights: [1, 2, 3]) == [0, 0, 0])
  }
}
