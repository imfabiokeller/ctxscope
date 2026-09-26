public import SwiftUI

/// A sidebar's content, scrolled when it is taller than the window, and
/// brought to `focus` when that changes: a session with a dozen cache breaks
/// otherwise pushes what was picked below the window's edge.
///
/// A scroll view renders as an empty box offscreen, so under the renderer
/// the content is laid out plainly from the top and clipped.
public struct SidebarScroll<Focus: Hashable, Content: View>: View {
  private let focus: Focus?
  private let content: Content
  @Environment(\.isRendering) private var isRendering

  /// `focus` is the id of a view inside `content`, brought into view when
  /// the sidebar appears and whenever it changes.
  public init(focus: Focus?, @ViewBuilder content: () -> Content) {
    self.focus = focus
    self.content = content()
  }

  public var body: some View {
    if isRendering {
      content.frame(maxHeight: .infinity, alignment: .top).clipped()
    } else {
      ScrollViewReader { proxy in
        ScrollView { content }
          .onAppear { reveal(focus, with: proxy) }
          .onChange(of: focus) { _, focus in reveal(focus, with: proxy) }
      }
    }
  }

  /// Scrolls just far enough for the focused view's foot to show, which
  /// keeps as much of what is above it in view as fits.
  private func reveal(_ focus: Focus?, with proxy: ScrollViewProxy) {
    guard let focus else { return }
    proxy.scrollTo(focus, anchor: .bottom)
  }
}

extension SidebarScroll where Focus == Never {
  /// Content with nothing to bring into view.
  public init(@ViewBuilder content: () -> Content) {
    self.init(focus: nil, content: content)
  }
}
