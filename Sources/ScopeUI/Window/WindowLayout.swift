public import SwiftUI

public struct WindowLayout<Header: View, Main: View, Sidebar: View>: View {
  private let header: Header
  private let main: Main
  private let sidebar: Sidebar
  @Environment(\.theme) private var theme

  public init(
    @ViewBuilder header: () -> Header, @ViewBuilder main: () -> Main,
    @ViewBuilder sidebar: () -> Sidebar
  ) {
    self.header = header()
    self.main = main()
    self.sidebar = sidebar()
  }

  public var body: some View {
    VStack(spacing: 0) {
      header
      HStack(spacing: 0) {
        theme.surface.window.color
          .overlay(alignment: .topLeading) { main }
        // The sidebar's width includes its rule, drawn over its own background.
        theme.surface.sidebar.color
          .overlay(alignment: .topLeading) {
            sidebar.padding(.leading, theme.metrics.hairline)
          }
          .frame(width: theme.metrics.window.sidebarWidth)
          .overlay(alignment: .leading) { Hairline(axis: .vertical) }
      }
    }
  }
}
