public import SwiftUI

/// Terms and their values in two columns, the popover's figures: terms in
/// primary text, values in the strong weight and held to the right, one line
/// each. The sidebars set their facts on tiles, with `FactGrid`.
public struct DefinitionList: View {
  public struct Entry: Identifiable {
    public let term: String
    public let value: Text
    public var id: String { term }

    /// The value is a `Text` so a caller can set part of it in a stronger
    /// weight or a quieter color. What it does not style is set in the
    /// list's own value style.
    public init(_ term: String, _ value: Text) {
      self.term = term
      self.value = value
    }

    public init(_ term: String, _ value: String) {
      self.init(term, Text(value))
    }
  }

  private let entries: [Entry]
  @Environment(\.theme) private var theme

  public init(_ entries: [Entry]) {
    self.entries = entries
  }

  public var body: some View {
    let list = theme.metrics.list
    VStack(alignment: .leading, spacing: list.popoverRowGap) {
      ForEach(entries) { entry in
        HStack(alignment: .top, spacing: list.columnGap) {
          // One line each, set in the theme's line height.
          Text(entry.term)
            .foregroundStyle(theme.text.primary.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .line(theme.type.lines.body)
          entry.value
            .font(theme.type.bodyStrong)
            .foregroundStyle(theme.text.primary.color)
            .fixedSize()
            .line(theme.type.lines.body)
        }
        .accessibilityElement(children: .combine)
      }
    }
    .font(theme.type.body)
  }
}

#Preview {
  DefinitionList([.init("This request", "$0.058"), .init("Session so far", "$3.94")])
    .frame(width: 296)
    .padding()
    .environment(\.theme, Theme.preview)
}
