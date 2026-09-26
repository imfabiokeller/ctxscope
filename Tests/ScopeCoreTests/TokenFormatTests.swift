import Testing

@testable import ScopeCore

@Suite("TokenFormat")
struct TokenFormatTests {
  @Test("token counts read the way the window writes them")
  func tokens() {
    #expect(TokenFormat.tokens(942) == "942")
    #expect(TokenFormat.tokens(1200) == "1.20k")
    #expect(TokenFormat.tokens(12_400) == "12.4k")
    #expect(TokenFormat.tokens(1_050_000) == "1.05M")
  }

  @Test("the menu bar's brief count")
  func brief() {
    #expect(TokenFormat.brief(942) == "942")
    #expect(TokenFormat.brief(9_640) == "9.6k")
    #expect(TokenFormat.brief(9_960) == "10k")
    #expect(TokenFormat.brief(142_600) == "143k")
    #expect(TokenFormat.brief(999_400) == "999k")
    #expect(TokenFormat.brief(999_600) == "1.0M")
    #expect(TokenFormat.brief(1_240_000) == "1.2M")
  }

  @Test("a token count is never shown without its grade")
  func grades() {
    #expect(TokenFormat.tokens(Tokens(1200, .derived)) == "1.20k D")
  }

  @Test("percentages")
  func percentages() {
    #expect(TokenFormat.percent(0.732) == "73%")
    #expect(TokenFormat.finePercent(0.0732) == "7.3%")
    #expect(TokenFormat.ratio(84.0, places: 0) == "84")
  }

  @Test("dollars read the way the window writes them")
  func dollars() {
    #expect(TokenFormat.dollars(3.9412) == "$3.94")
    #expect(TokenFormat.dollars(0.39) == "$0.39")
    #expect(TokenFormat.dollars(0.0581) == "$0.058")
    #expect(TokenFormat.dollars(0.00427) == "$0.0043")
    #expect(TokenFormat.dollars(0) == "$0.00")
    #expect(TokenFormat.dollars(-0.17) == "-$0.17")
  }

  @Test("short sizes and cents read the way the window writes them")
  func short() {
    #expect(TokenFormat.short(3100) == "3.1k")
    #expect(TokenFormat.short(142_600) == "142.6k")
    #expect(TokenFormat.short(942) == "942")
    #expect(TokenFormat.short(1_050_000) == "1.05M")
    #expect(TokenFormat.cents(0.0581) == "$0.06")
    #expect(TokenFormat.cents(3.9412) == "$3.94")
  }
}
