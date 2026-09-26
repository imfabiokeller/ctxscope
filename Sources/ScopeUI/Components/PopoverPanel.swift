public import SwiftUI

/// The border sits outside the content, so the panel is two points wider.
public struct PopoverPanel<Content: View>: View {
  private let content: Content
  @Environment(\.theme) private var theme

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    let popover = theme.metrics.popover
    let hairline = theme.metrics.hairline
    let shape = RoundedRectangle(cornerRadius: popover.cornerRadius)
    let shadow = theme.shadow.popover
    content
      .frame(width: popover.width)
      .clipShape(RoundedRectangle(cornerRadius: popover.cornerRadius - hairline))
      .padding(hairline)
      .background {
        shape.fill(theme.surface.popover.color)
          .shadow(color: shadow.color.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
      }
      .overlay { shape.strokeBorder(theme.line.popover.color, lineWidth: hairline) }
  }

}

extension Theme.ShadowRole {
  public var reach: Metrics.Edges {
    Metrics.Edges(top: max(0, blur - y), horizontal: blur + abs(x), bottom: max(0, blur + y))
  }
}

#Preview {
  PopoverPanel {
    Text("retry-policy").padding(16).frame(maxWidth: .infinity, alignment: .leading)
  }
  .padding(40)
  .environment(\.theme, Theme.preview)
}
