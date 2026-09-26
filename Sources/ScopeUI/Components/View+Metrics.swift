internal import SwiftUI

extension View {
  func padding(_ insets: Metrics.Insets) -> some View {
    padding(.vertical, insets.vertical).padding(.horizontal, insets.horizontal)
  }

  func line(_ height: CGFloat) -> some View {
    frame(height: height)
  }

  func padding(_ edges: Metrics.Edges) -> some View {
    padding(
      EdgeInsets(
        top: edges.top, leading: edges.horizontal, bottom: edges.bottom,
        trailing: edges.horizontal))
  }
}
