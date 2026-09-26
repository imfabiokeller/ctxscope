internal import SwiftUI

/// The popover with no session in focus: how to focus one from a chat, the
/// sessions written to most recently, and a way into the window or out of
/// the app.
struct EmptyPopoverView: View {
  let content: EmptyPopover
  let actions: PopoverActions
  @Environment(\.theme) private var theme

  var body: some View {
    let popover = theme.metrics.popover
    let lines = theme.type.lines
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: popover.emptyGap) {
        Text("No session in focus")
          .font(theme.type.heading)
          .foregroundStyle(theme.text.primary.color)
          .line(lines.heading)
        Text("Type this in the Claude Code chat you want to see:")
          .font(theme.type.body)
          .foregroundStyle(theme.text.supporting.color)
          .lineLimit(1)
          .line(lines.prose)
        HStack(spacing: theme.metrics.control.buttonGap) {
          InlineCode(content.command)
          Button("Copy") { actions.copy(content.command) }
            .buttonStyle(.borderedPush(.tall))
        }
      }
      .padding(popover.emptyPadding)
      if !content.recent.isEmpty {
        Hairline(.divider)
        RecentSessions(sessions: content.recent, pick: actions.pick)
      }
      PanelFooter(.text) {
        Button("Open window", action: actions.openWindow).buttonStyle(.textLink)
        Spacer(minLength: 0)
        Button("Quit ctxscope", action: actions.quit).buttonStyle(.textLink(.plain))
      }
    }
  }
}

/// The recent sessions, one row each: name, folder and length, and when.
private struct RecentSessions: View {
  let sessions: [RecentSession]
  let pick: (String) -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    let popover = theme.metrics.popover
    let lines = theme.type.lines
    VStack(alignment: .leading, spacing: 0) {
      Text("Or pick a recent session")
        .font(theme.type.caption)
        .foregroundStyle(theme.text.secondary.color)
        .line(lines.caption)
        .padding(popover.listHeader)
      ForEach(sessions) { session in
        Button {
          pick(session.id)
        } label: {
          HStack(spacing: popover.rowGap) {
            VStack(alignment: .leading, spacing: popover.rowTextGap) {
              Text(session.name)
                .font(theme.type.bodyMedium)
                .foregroundStyle(theme.text.primary.color)
                .line(lines.body)
              Text(session.detail)
                .font(theme.type.small)
                .foregroundStyle(theme.text.secondary.color)
                .line(lines.small)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(session.ago)
              .font(theme.type.caption)
              .foregroundStyle(theme.text.secondary.color)
              .line(lines.caption)
          }
        }
        .buttonStyle(.listRow)
      }
    }
    .padding(popover.listPadding)
  }
}
