public import SwiftUI

/// The window's frame of parts: the header across the top, then a flexible
/// main column and a fixed sidebar with its own background.
///
/// A page fills the two columns and brings its own padding, because the
/// pages space their content differently.
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
      // Each column is its background, sized by the layout, with the page
      // laid over it. The page is offered the column's whole size, and an
      // empty column still takes its place.
      HStack(spacing: 0) {
        theme.surface.window.color
          .overlay(alignment: .topLeading) { main }
        // The sidebar's width includes its rule, which is drawn over its own
        // background.
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
