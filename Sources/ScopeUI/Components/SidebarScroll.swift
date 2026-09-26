public import SwiftUI

/// A scroll view renders as an empty box offscreen, so the renderer clips instead.
public struct SidebarScroll<Focus: Hashable, Content: View>: View {
  private let focus: Focus?
  private let content: Content
  @Environment(\.isRendering) private var isRendering

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

  private func reveal(_ focus: Focus?, with proxy: ScrollViewProxy) {
    guard let focus else { return }
    proxy.scrollTo(focus, anchor: .bottom)
  }
}

extension SidebarScroll where Focus == Never {
  public init(@ViewBuilder content: () -> Content) {
    self.init(focus: nil, content: content)
  }
}
