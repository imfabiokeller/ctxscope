public import SwiftUI

/// What a click on the menu bar item opens: the session in focus, its size
/// by kind, what it costs, its last cache break and its context per request;
/// or, with none in focus, how to pick one.
///
/// It draws what it is given and says which button was pressed. Everything
/// it shows is worked out by `PopoverPresenter`, and the panel it sits in is
/// the application's.
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

/// The popover as the application shows it: it follows the model and the
/// theme for as long as it is open, one hosting view for all of it, and
/// asks the presenter again whenever either changes.
public struct StatusPopoverHost: View {
  private let model: InstrumentModel
  /// The store, not one theme: the popover stays open while the system
  /// switches appearance, and a theme captured when it opened would not.
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
    // The time is taken when the content is asked for, which is when the
    // popover opens and when the model changes, so "12 s ago" is as old as
    // what it describes and nothing ticks.
    let context = PopoverPresenter.Context(now: Date(), home: home)
    StatusPopover(content: PopoverSource.content(of: model, context: context), actions: actions)
      .environment(\.theme, themes.theme)
  }
}
