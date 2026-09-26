public import SwiftUI

/// A pop-up button in the window's header: a title, a quieter subtitle and a
/// chevron, opening a real menu.
///
/// A native `Menu` in button style, so the menu, its keyboard handling and
/// its accessibility are the system's. Only the face is the theme's, through
/// a button style, which is also what lets it render offscreen.
public struct ToolbarPopUpButton<Items: View>: View {
  private let title: String
  private let subtitle: String?
  private let emphasized: Bool
  private let items: Items
  @Environment(\.theme) private var theme

  /// `emphasized` sets the title in the strong weight, the way the session's
  /// name is set.
  public init(
    title: String, subtitle: String? = nil, emphasized: Bool = false,
    @ViewBuilder items: () -> Items
  ) {
    self.title = title
    self.subtitle = subtitle
    self.emphasized = emphasized
    self.items = items()
  }

  public var body: some View {
    let control = theme.metrics.control
    Menu {
      items
    } label: {
      HStack(spacing: control.popUpGap) {
        Text(title).font(emphasized ? theme.type.bodyStrong : theme.type.body)
        if let subtitle {
          Text(subtitle).font(theme.type.body).foregroundStyle(theme.text.tertiary.color)
        }
        GlyphView(.chevronDown, side: control.chevron, stroke: control.chevronStroke)
      }
      .lineLimit(1)
    }
    .menuStyle(.button)
    .menuIndicator(.hidden)
    .buttonStyle(ToolbarControlStyle())
    .fixedSize()
    .accessibilityLabel(title)
    .accessibilityValue(subtitle ?? "")
  }
}

/// The face of a header control: white, a slightly lighter border than a
/// push button's, and less padding.
struct ToolbarControlStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    ToolbarControlFace(configuration: configuration)
  }
}

private struct ToolbarControlFace: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.theme) private var theme

  var body: some View {
    let control = theme.metrics.control
    let shape = RoundedRectangle(cornerRadius: control.cornerRadius)
    configuration.label
      .foregroundStyle(theme.text.primary.color)
      // The padding is inside the border.
      .padding(.horizontal, control.popUpPadding + theme.metrics.hairline)
      .frame(height: control.height)
      .background {
        shape.fill(theme.control.fill.color)
        if configuration.isPressed {
          shape.fill(theme.control.pressed.color)
        }
      }
      .overlay {
        shape.strokeBorder(theme.line.toolbarControl.color, lineWidth: theme.metrics.hairline)
      }
      .contentShape(shape)
  }
}

#Preview {
  HStack(spacing: 16) {
    ToolbarPopUpButton(title: "retry-policy", subtitle: "~/code/api-client", emphasized: true) {
      Button("helm-chart-bump") {}
    }
    ToolbarPopUpButton(title: "Lane: main", subtitle: "+ 2 subagents") {
      Button("Main") {}
    }
  }
  .padding()
  .environment(\.theme, Theme.preview)
}
