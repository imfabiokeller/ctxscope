public import SwiftUI

public struct StatusPopover: View {
  private let content: PopoverContent
  private let actions: PopoverActions

  public init(content: PopoverContent, actions: PopoverActions) {
    self.content = content
    self.actions = actions
  }

  public var body: some View {
    PopoverPanel {
      switch content {
      case .focused(let focused):
        FocusedPopoverView(content: focused, actions: actions)
      case .empty(let empty):
        EmptyPopoverView(content: empty, actions: actions)
      }
    }
    .fixedSize()
  }
}

public struct StatusPopoverHost: View {
  private let model: InstrumentModel
  /// The store, not one theme: the popover stays open while the appearance changes.
  private let themes: ThemeStore
  private let home: String
  private let actions: PopoverActions

  public init(
    model: InstrumentModel, themes: ThemeStore, home: String, actions: PopoverActions
  ) {
    self.model = model
    self.themes = themes
    self.home = home
    self.actions = actions
  }

  public var body: some View {
    let context = PopoverPresenter.Context(now: Date(), home: home)
    StatusPopover(content: PopoverSource.content(of: model, context: context), actions: actions)
      .environment(\.theme, themes.theme)
  }
}
