import Foundation
import ScopeCore
import ScopeUI
import SwiftUI

/// The menu bar item, on a light bar and on a dark one, in each of its three
/// states, at 1x and 2x.
///
/// The pixels are the item's own: every shot goes through `StatusFace` and
/// `StatusRender`, which are what the application puts in the bar, and the
/// template image is tinted with the bar's ink, which is what the system
/// makes of it there. The layout around the mark, its padding and the gap to
/// the number, is the system's in the app and drawn to match it here.
///
/// The mark is rendered at the shot's scale and magnified without smoothing,
/// so a 1x shot shows the pixels of a 1x display rather than a shrunk 2x one.
@MainActor
enum StatusShot {
  /// How much bigger than life the picture is drawn.
  static let magnification: CGFloat = 4
  /// Room for the item on its bar, in points.
  static let barWidth: CGFloat = 90

  struct Shot {
    let name: String
    let view: AnyView
    let size: CGSize
  }

  /// The three states, each from a reading the way the bar builds it.
  static let states: [(name: String, face: StatusFace)] = [
    ("focused", StatusFace(reading: reading(isLive: true))),
    ("idle", StatusFace(reading: reading(isLive: false))),
    ("none", StatusFace(reading: nil)),
  ]

  /// The sample session: 142.6k of a 200k window.
  static func reading(isLive: Bool) -> StatusReading {
    StatusReading(isLive: isLive, totalTokens: 142_600, window: 200_000)
  }

  /// Every state on the bar of each theme, which is a light bar and a dark
  /// one.
  static func all(themes: [Theme]) -> [Shot] {
    let bar = Metrics.standard.menuBar
    let size = CGSize(width: barWidth * magnification, height: bar.height * magnification)
    var shots: [Shot] = []
    for scale in [CGFloat(1), 2] {
      for theme in themes {
        for state in states {
          let item = MenuBarItem(face: state.face, scale: scale)
            .frame(width: barWidth, height: bar.height)
            .background(MenuBarBackground())
            .scaleEffect(magnification, anchor: .topLeading)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.theme, theme)
          shots.append(
            Shot(
              name: "status-\(state.name)-\(theme.appearance.rawValue)-bar-\(Int(scale))x",
              view: AnyView(item), size: size))
        }
      }
    }
    return shots
  }
}

/// The item as a bar shows it: the mark's own pixels and its number in the
/// bar's ink, laid out the way the system lays out its button.
struct MenuBarItem: View {
  let face: StatusFace
  let scale: CGFloat
  @Environment(\.theme) private var theme

  var body: some View {
    let bar = theme.metrics.menuBar
    HStack(spacing: bar.itemGap) {
      if let drawn = StatusRender.image(face, ink: theme.text.primary, scale: scale) {
        Image(decorative: drawn, scale: 1)
          .renderingMode(.template)
          .resizable()
          .interpolation(.none)
          .frame(width: StatusGlyph.size.width, height: StatusGlyph.size.height)
      }
      if let number = face.number {
        Text(number).font(theme.type.body).frame(height: theme.type.lines.body)
      }
    }
    .foregroundStyle(theme.text.primary.color)
    .padding(.horizontal, bar.itemPadding)
    .frame(height: bar.itemHeight)
  }
}

/// The desktop showing through a translucent menu bar.
struct MenuBarBackground: View {
  @Environment(\.theme) private var theme

  var body: some View {
    ZStack {
      theme.chrome.desktop.color
      theme.chrome.menuBar.color
    }
  }
}
