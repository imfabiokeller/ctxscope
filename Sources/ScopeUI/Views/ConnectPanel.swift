package import SwiftUI

package struct ConnectPanel: View {
  /// Held, not `@State`: under the offscreen renderer a `@State` model reads its
  /// initial values and shows a stale diff.
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
