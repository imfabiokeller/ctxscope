public import SwiftUI

/// A one point rule. Named for its role rather than drawn as a `Divider`,
/// whose color and thickness are the system's.
public struct Hairline: View {
  public enum Role: Sendable {
    /// Under the header, beside the sidebar, around a table's header.
    case hairline
    /// Between groups inside a panel.
    case divider
    /// Between the rows of a table.
    case row
  }

  private let role: Role
  private let axis: Axis
  @Environment(\.theme) private var theme

  public init(_ role: Role = .hairline, axis: Axis = .horizontal) {
    self.role = role
    self.axis = axis
  }

  public var body: some View {
    let line = theme.line
    let color =
      switch role {
      case .hairline: line.hairline
      case .divider: line.divider
      case .row: line.row
      }
    let thickness = theme.metrics.hairline
    Rectangle()
      .fill(color.color)
      .frame(
        width: axis == .vertical ? thickness : nil,
        height: axis == .horizontal ? thickness : nil
      )
      .accessibilityHidden(true)
  }
}

/// The grey bar at the bottom of a panel, with a divider above it.
public struct PanelFooter<Content: View>: View {
  public enum Inset: Sendable {
    /// Holding buttons, which bring their own height.
    case buttons
    /// Holding text-only buttons.
    case text
  }

  private let inset: Inset
  private let content: Content
  @Environment(\.theme) private var theme

  public init(_ inset: Inset = .buttons, @ViewBuilder content: () -> Content) {
    self.inset = inset
    self.content = content()
  }

  public var body: some View {
    let popover = theme.metrics.popover
    VStack(spacing: 0) {
      Hairline(.divider)
      HStack(spacing: theme.metrics.control.buttonGap) { content }
        .frame(maxWidth: .infinity)
        .padding(inset == .buttons ? popover.footerButtons : popover.footerText)
    }
    .background(theme.surface.popoverFooter.color)
  }
}

#Preview {
  VStack(spacing: 0) {
    Hairline()
    Spacer().frame(height: 40)
    PanelFooter {
      Button("Change session…") {}.buttonStyle(.borderedPush)
    }
  }
  .frame(width: 360)
  .environment(\.theme, Theme.preview)
}
