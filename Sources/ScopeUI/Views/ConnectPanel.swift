package import SwiftUI

/// The Connect panel: what is connected, the exact diff, and one button that
/// reads Connect or Disconnect.
///
/// Plain words and nothing explained at length. What the button would write is
/// on screen before it writes it.
package struct ConnectPanel: View {
  /// Held, not owned. The window and the snapshot tool make the model; a
  /// `@State` of it reads its initial values under the offscreen renderer,
  /// and the panel then shows a diff that has already been worked out as
  /// though it had not been.
  private let model: ConnectModel
  @Environment(\.theme) private var theme

  package init(model: ConnectModel) {
    self.model = model
  }

  package var body: some View {
    let connect = theme.metrics.connect
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: connect.gap) {
        FactsView(facts: facts)
        notes
        // A file ctxscope will not touch has no diff to show, and a line
        // saying nothing changes under a line saying why reads like a
        // contradiction.
        if model.plan != nil {
          if model.diff.isEmpty {
            note("Nothing in the settings file changes.", theme.text.secondary)
          } else {
            CodeBlock(model.diff, height: .filling)
          }
        }
      }
      .padding(connect.padding)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      PanelFooter {
        if let done = model.done { note(done, theme.text.secondary) }
        Spacer(minLength: 0)
        Button(model.buttonTitle) { model.act() }
          .buttonStyle(.borderedPush)
          .disabled(model.plan == nil)
      }
    }
    .background(theme.surface.window.color)
  }

  /// The hooks on a row of their own, because their state can be a long
  /// line, and the transcripts and the skill beside each other under them.
  private var facts: [FactData] {
    [
      FactData("Hooks", model.hooks.text, wide: true),
      FactData("Transcripts", "On"),
      FactData("Skill", skillText),
    ]
  }

  private var skillText: String {
    switch model.skill {
    case .none: "Not installed"
    case .ours: "/ctxscope opens the window"
    case .edited: "Edited by hand, left alone"
    }
  }

  /// What the hooks need, the copy of the settings file, and what failed:
  /// all under the tiles, because they are about what the button does.
  @ViewBuilder
  private var notes: some View {
    let lines = [
      model.hint.map { ($0, theme.text.secondary) },
      model.backupNote.map { ($0, theme.text.secondary) },
      model.failure.map { ($0, theme.text.failure) },
    ].compactMap(\.self)
    if !lines.isEmpty {
      VStack(alignment: .leading, spacing: theme.metrics.connect.noteGap) {
        ForEach(lines, id: \.0) { note($0.0, $0.1) }
      }
    }
  }

  private func note(_ text: String, _ color: ThemeColor) -> some View {
    Text(text)
      .font(theme.type.caption)
      .foregroundStyle(color.color)
      .fixedSize(horizontal: false, vertical: true)
  }
}
