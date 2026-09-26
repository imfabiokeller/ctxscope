import Testing

@testable import ScopeCore

@Suite("Grade")
struct GradeTests {
  @Test("measured is stronger than derived, derived than estimated")
  func ordering() {
    #expect(Grade.measured < Grade.derived)
    #expect(Grade.derived < Grade.estimated)
    #expect(max(Grade.measured, .derived) == .derived)
  }

  @Test("adding tokens keeps the weakest grade")
  func adding() {
    let sum = Tokens(10, .measured) + Tokens(5, .estimated)
    #expect(sum.value == 15)
    #expect(sum.grade == .estimated)
  }
}
