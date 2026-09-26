import Foundation
import Testing

@testable import ScopeUI

@Suite("Design tokens")
struct DesignTokenTests {
  private static func textPairs(_ theme: Theme) -> [(String, ThemeColor, ThemeColor)] {
    let text = theme.text
    let surface = theme.surface
    let reading = [
      ("window", surface.window), ("header", surface.header), ("sidebar", surface.sidebar),
      ("raised", surface.raised), ("popover", surface.popover),
      ("popover footer", surface.popoverFooter), ("control", theme.control.fill),
      ("a fact's tile", surface.tile),
    ]
    var pairs: [(String, ThemeColor, ThemeColor)] = []
    for (name, color) in [
      ("primary", text.primary), ("supporting", text.supporting),
      ("secondary", text.secondary),
    ] {
      for (place, background) in reading {
        pairs.append(("\(name) on \(place)", color, background))
      }
    }
    // Tertiary is only set on a control's face and on the bar and window controls stand on.
    for (place, background) in reading.prefix(4) + [("control", theme.control.fill)] {
      pairs.append(("tertiary on \(place)", text.tertiary, background))
    }
    return pairs + [
      ("primary on a selected row", text.primary, surface.selection),
      ("secondary on a selected row", text.secondary, surface.selection),
      ("unused on a selected row", text.unused, surface.selection),
      ("unused on the window", text.unused, surface.window),
      ("primary on the thumb", text.primary, theme.control.thumb),
      ("code on the code box", text.code, surface.code),
      ("primary on inline code", text.primary, surface.inlineCode),
      ("link on the sidebar", text.link, surface.sidebar),
      ("link on the popover footer", text.link, surface.popoverFooter),
      ("on accent", text.onAccent, theme.control.accent),
      ("a failure on the window", text.failure, surface.window),
      ("a failure on the popover footer", text.failure, surface.popoverFooter),
      ("live ink on its pill", theme.status.liveInk, theme.status.liveFill),
      ("live ink on the popover", theme.status.liveInk, surface.popover),
      ("a badge's digit", theme.status.onBadge, theme.status.badge),
      ("a prompt's number", theme.chart.phaseInk, theme.chart.phase),
      ("the selected prompt's number", theme.chart.phaseInkSelected, theme.chart.phaseSelected),
    ]
  }

  @Test("every text role holds 4.5:1 where it is set, in both appearances")
  func textContrast() {
    for theme in ThemeLoader.bundled() {
      for (name, ink, background) in Self.textPairs(theme) {
        let ratio = Contrast.ratio(ink, on: background)
        #expect(ratio >= Contrast.text, "\(theme.name): \(name) is \(ratio)")
      }
    }
  }

  @Test("a disabled control is fainter than text and still visible")
  func disabled() {
    for theme in ThemeLoader.bundled() {
      let disabled = Contrast.ratio(theme.text.disabled, on: theme.surface.header)
      let secondary = Contrast.ratio(theme.text.secondary, on: theme.surface.header)
      #expect(disabled < secondary, "\(theme.name)")
      #expect(disabled >= 1.5, "\(theme.name): disabled is \(disabled)")
    }
  }

  @Test("the six kind colors differ and stand off the chart track")
  func kinds() {
    for theme in ThemeLoader.bundled() {
      let kinds = theme.kind.inReadingOrder
      #expect(Set(kinds).count == 6, "\(theme.name)")
      for kind in kinds {
        #expect(Contrast.ratio(kind, on: theme.chart.track) >= 1.3, "\(theme.name) \(kind)")
      }
    }
  }

  @Test("a kind keeps its hue across appearances")
  func kindHues() throws {
    let themes = ThemeLoader.bundled()
    let light = try #require(themes.first { $0.appearance == .light })
    let dark = try #require(themes.first { $0.appearance == .dark })
    let pairs = zip(light.kind.inReadingOrder, dark.kind.inReadingOrder)
    for (one, other) in pairs where saturation(one) > 0.3 {
      let distance = abs(hue(one) - hue(other))
      #expect(min(distance, 360 - distance) < 12, "\(one) against \(other)")
    }
  }

  @Test("the light theme holds the values it was drawn with")
  func lightValues() throws {
    let light = try #require(ThemeLoader.bundled().first { $0.appearance == .light })
    #expect(light.surface.header == Contrast.color("#F6F6F8"))
    #expect(light.text.secondary == Contrast.color("#5F5F64"))
    #expect(light.kind.results == Contrast.color("#8A63D2"))
    #expect(light.chart.dimmedOpacity == 0.42)
    #expect(light.shadow.thumb.radius == 1)
    #expect(light.metrics.header.height == 52)
  }

  private func hue(_ color: ThemeColor) -> Double {
    let high = max(color.red, color.green, color.blue)
    let low = min(color.red, color.green, color.blue)
    let span = high - low
    guard span > 0 else { return 0 }
    let raw: Double =
      high == color.red
      ? (color.green - color.blue) / span
      : high == color.green
        ? 2 + (color.blue - color.red) / span : 4 + (color.red - color.green) / span
    let degrees = raw * 60
    return degrees < 0 ? degrees + 360 : degrees
  }

  private func saturation(_ color: ThemeColor) -> Double {
    let high = max(color.red, color.green, color.blue)
    let low = min(color.red, color.green, color.blue)
    return high == 0 ? 0 : (high - low) / high
  }
}
