import Foundation
import ScopeCore
import Testing

@testable import ScopeUI

@Suite("Theme")
struct ThemeTests {
  @MainActor
  private var store: ThemeStore { ThemeStore(appearance: .dark) }

  @Test("dark and light both load out of the bundle")
  @MainActor
  func bundledThemes() {
    let store = self.store
    #expect(ThemeLoader.bundled().contains { $0.name == "dark" })
    #expect(ThemeLoader.bundled().contains { $0.name == "light" })
    #expect(store.theme.name == "dark")
  }

  @Test("the theme is whatever the system is showing")
  @MainActor
  func followsSystem() {
    let store = self.store
    store.follow(system: .light)
    #expect(store.theme.name == "light")
    store.follow(system: .dark)
    #expect(store.theme.name == "dark")
  }

  @Test("the three color notations a theme file uses all parse")
  func colorNotations() throws {
    let hex = try #require(ThemeColor("#16171B"))
    #expect(abs(hex.red - 22.0 / 255) < 0.001)
    #expect(hex.alpha == 1)

    let rgba = try #require(ThemeColor("rgba(255,255,255,.075)"))
    #expect(rgba.red == 1)
    #expect(abs(rgba.alpha - 0.075) < 0.0001)

    // A known OKLCH: mid lightness, no chroma, is a neutral grey.
    let grey = try #require(ThemeColor("oklch(0.5 0 0)"))
    #expect(abs(grey.red - grey.green) < 0.001)
    #expect(abs(grey.green - grey.blue) < 0.001)
    // OKLab lightness 0.5 is 0.125 in linear light, which is 0.389 once the
    // sRGB transfer function has been applied.
    #expect(abs(grey.red - 0.389) < 0.002)

    #expect(ThemeColor("not a color") == nil)
  }

  @Test("white and black come back out of the conversion")
  func conversionEnds() {
    let white = OKLCH(lightness: 1, chroma: 0, hue: 0).displayComponents()
    #expect(abs(white.red - 1) < 0.002)
    #expect(abs(white.blue - 1) < 0.002)
    let black = OKLCH(lightness: 0, chroma: 0, hue: 0).displayComponents()
    #expect(black.red == 0)
    #expect(black.green == 0)
  }

  @Test("a channel outside its range is a typo, not a color")
  func outOfRange() {
    #expect(ThemeColor("rgb(900,-20,300)") == nil)
    #expect(ThemeColor("rgba(10,10,10,4)") == nil)
    #expect(ThemeColor("oklch(2 0.1 30)") == nil)
    #expect(ThemeColor("oklch(0.5 -1 30)") == nil)
    #expect(ThemeColor("#12345") == nil)
    // And the ones that are colors still are.
    #expect(ThemeColor("rgba(255,255,255,.075)") != nil)
    #expect(ThemeColor("oklch(0.72 0.19 25)") != nil)
  }
}
