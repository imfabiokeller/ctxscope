internal import SwiftUI

/// The metrics and the line heights, applied to a view.
extension View {
  /// Vertical and horizontal padding from one of the metrics' insets.
  func padding(_ insets: Metrics.Insets) -> some View {
    padding(.vertical, insets.vertical).padding(.horizontal, insets.horizontal)
  }

  /// One line of text set in the theme's line height for its size, one of
  /// `Typography.lines`, rather than SwiftUI's.
  func line(_ height: CGFloat) -> some View {
    frame(height: height)
  }

  /// Padding from one of the metrics' insets whose top and bottom differ.
  func padding(_ edges: Metrics.Edges) -> some View {
    padding(
      EdgeInsets(
        top: edges.top, leading: edges.horizontal, bottom: edges.bottom,
        trailing: edges.horizontal))
  }
}
