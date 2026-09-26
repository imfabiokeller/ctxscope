import Foundation
import ScopeCore
import ScopeUI
import SwiftUI

@MainActor
enum StatusShot {
  static let magnification: CGFloat = 4
  static let barWidth: CGFloat = 90

  struct Shot {
    let name: String
    let view: AnyView
    let size: CGSize
  }

  static let states: [(name: String, face: StatusFace)] = [
    ("focused", StatusFace(reading: reading(isLive: true))),
    ("idle", StatusFace(reading: reading(isLive: false))),
    ("none", StatusFace(reading: nil)),
  ]

  static func reading(isLive: Bool) -> StatusReading {
    StatusReading(isLive: isLive, totalTokens: 142_600, window: 200_000)
  }

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

struct MenuBarBackground: View {
  @Environment(\.theme) private var theme

  var body: some View {
    ZStack {
      theme.chrome.desktop.color
      theme.chrome.menuBar.color
    }
  }
}
