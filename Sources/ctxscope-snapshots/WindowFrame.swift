import ScopeUI
import SwiftUI

// The system draws the window frame in the app, so it lives here and not in ScopeUI.
struct WindowFrame<Content: View>: View {
  let content: Content
  @Environment(\.theme) private var theme

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    let window = theme.metrics.window
    let hairline = theme.metrics.hairline
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: window.cornerRadius - hairline))
      .overlay(alignment: .topLeading) { TrafficLights() }
      .padding(hairline)
      .background(
        RoundedRectangle(cornerRadius: window.cornerRadius).fill(theme.surface.window.color)
      )
      .overlay {
        RoundedRectangle(cornerRadius: window.cornerRadius)
          .strokeBorder(theme.chrome.windowBorder.color, lineWidth: hairline)
      }
      .frame(width: window.size.width, height: window.size.height)
      .background(theme.surface.window.color)
  }
}

private struct TrafficLights: View {
  @Environment(\.theme) private var theme

  var body: some View {
    let window = theme.metrics.window
    let header = theme.metrics.header
    HStack(spacing: window.trafficLightGap) {
      ForEach([theme.chrome.close, theme.chrome.minimize, theme.chrome.zoom], id: \.self) {
        Circle().fill($0.color).frame(width: window.trafficLight, height: window.trafficLight)
      }
    }
    .padding(.leading, header.padding)
    .frame(height: header.height)
  }
}
