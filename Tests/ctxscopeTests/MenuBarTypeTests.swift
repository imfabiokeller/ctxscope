import AppKit
import ScopeCore
import Testing

@testable import ctxscope

/// The item sits in a row of other items, and every point it gains pushes all
/// of them along. Measured on the real bar it went 67, 60, 67 points as its
/// number gained a digit and lost it again.
@Suite("the number in the bar")
@MainActor
struct MenuBarTypeTests {
  private func width(_ tokens: Int?) -> CGFloat {
    MenuBarType.number(tokens.map(TokenFormat.brief)).size().width
  }

  @Test("fewer digits take the room of three")
  func fixedWidth() {
    let three = width(142_600)
    for tokens in [12_000, 48_000, 99_000, 143_000, 999_000] {
      #expect(abs(width(tokens) - three) < 0.01, "\(tokens) is a different width")
    }
  }

  @Test("nothing to count is no number at all")
  func noNumber() {
    #expect(MenuBarType.number(nil).string.isEmpty)
    #expect(width(nil) == 0)
  }

  @Test("the number is the brief count, after a space")
  func text() {
    #expect(MenuBarType.number("143k").string == " 143k")
    #expect(MenuBarType.number("48k").string == " \(MenuBarType.figureSpace)48k")
  }

  @Test("the digits are tabular, so a number does not shift as it changes")
  func tabular() {
    let font = MenuBarType.number
    #expect(font.pointSize == NSFont.systemFontSize)
    let one = NSAttributedString(string: "1", attributes: [.font: font]).size().width
    let eight = NSAttributedString(string: "8", attributes: [.font: font]).size().width
    #expect(abs(one - eight) < 0.01)
    // And the space that holds a digit's room is a digit wide.
    let space = NSAttributedString(
      string: MenuBarType.figureSpace, attributes: [.font: font]
    ).size().width
    #expect(abs(space - one) < 0.01)
  }
}
