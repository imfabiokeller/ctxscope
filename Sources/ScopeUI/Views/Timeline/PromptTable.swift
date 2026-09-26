internal import SwiftUI

/// "By prompt": one row per prompt, the selected one marked. Selecting a row
/// selects its prompt.
struct PromptTable: View {
  let prompts: [PromptRow]
  let onSelect: (Int) -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    let widths = theme.metrics.table.prompts
    DataTable(
      prompts,
      selection: Binding(
        get: { prompts.first(where: \.isSelected)?.id },
        set: { if let id = $0 { onSelect(id) } }),
      density: .compact,
      columns: [
        DataColumn(TimelineWords.number, width: .fixed(widths.number)) { row in
          Text(row.number).foregroundStyle(theme.text.secondary.color)
        },
        DataColumn(TimelineWords.prompt, text: \.prompt),
        DataColumn(
          TimelineWords.requests, width: .fixed(widths.requests), alignment: .trailing,
          text: \.range),
        DataColumn(
          TimelineWords.added, width: .fixed(widths.added), alignment: .trailing, text: \.added),
        DataColumn(
          TimelineWords.costColumn, width: .fixed(widths.cost), alignment: .trailing,
          text: \.cost),
        DataColumn(
          TimelineWords.breaksColumn, width: .fixed(widths.breaks), alignment: .trailing,
          text: \.breaks),
      ]
    )
  }
}
