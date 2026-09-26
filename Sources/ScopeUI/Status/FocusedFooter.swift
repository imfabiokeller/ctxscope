internal import SwiftUI

/// The buttons under a session in focus: open the window, pick another
/// session, and the rest of what the item can do behind "More".
struct FocusedFooter: View {
  let others: [RecentSession]
  let actions: PopoverActions
  @Environment(\.theme) private var theme

  var body: some View {
    PanelFooter {
      Button(action: actions.openWindow) {
        Text("Open window").frame(maxWidth: .infinity)
      }
      .buttonStyle(.primaryPush)
      .keyboardShortcut(.defaultAction)
      Menu {
        if others.isEmpty {
          Text("No other sessions")
        }
        ForEach(others) { session in
          Button("\(session.name)  \(session.detail)") { actions.pick(session.id) }
        }
      } label: {
        Text("Change session\u{2026}")
      }
      .menuStyle(.button)
      .menuIndicator(.hidden)
      .buttonStyle(.borderedPush)
      .fixedSize()
      Menu {
        Button("Connect", action: actions.connect)
        Divider()
        Button("Turn off ctxscope", action: actions.turnOff)
        Button("Quit ctxscope", action: actions.quit)
      } label: {
        GlyphView(.ellipsis, side: theme.metrics.control.ellipsis)
      }
      .menuStyle(.button)
      .menuIndicator(.hidden)
      .buttonStyle(.iconPush)
      .fixedSize()
      .accessibilityLabel("More")
    }
  }
}
