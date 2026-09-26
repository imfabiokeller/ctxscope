internal import ScopeCore
internal import SwiftUI

/// The Blocks section: its line with the filter and the text filter, and the
/// table, largest first. Selecting a row selects its block, and a selection
/// made anywhere else marks the row it is listed under.
struct BlocksSection: View {
  let blocks: BlocksData
  @Binding var filter: BlockFilter
  @Binding var query: String
  @Binding var selection: SegmentID?
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: theme.metrics.contextPage.blocksHeaderGap) {
      SectionHeader(blocks.title, detail: Text(blocks.detail), layout: .inline) {
        SegmentedPicker(
          blocks.filterLabel, selection: $filter, options: BlockFilter.allCases, size: .filter,
          title: \.rawValue)
        SearchField(blocks.searchLabel, prompt: blocks.searchPrompt, text: $query)
      }
      DataTable(blocks.rows, selection: rowSelection, columns: columns)
    }
  }

  private var rowSelection: Binding<SegmentID?> {
    Binding(
      get: { selection.flatMap { blocks.row(containing: $0)?.id } },
      set: { selection = $0 })
  }

  /// "no" in its own color, "not tracked" quieter than a fact.
  private func ink(_ use: BlockUse) -> ThemeColor {
    switch use {
    case .used: theme.text.primary
    case .unused: theme.text.unused
    case .notTracked: theme.text.secondary
    }
  }

  private var columns: [DataColumn<BlockRowData>] {
    let widths = theme.metrics.table.blocks
    let titles = blocks.columns
    return [
      DataColumn(titles.kind, width: .fixed(widths.kind)) { row in
        KindLegendItem(
          color: theme.color(of: row.kind), name: row.kindName,
          style: .table)
      },
      DataColumn(titles.block) { $0.label },
      DataColumn(titles.size, width: .fixed(widths.size), alignment: .trailing) { $0.size },
      DataColumn(titles.carried, width: .fixed(widths.carried), alignment: .trailing) {
        $0.carried
      },
      DataColumn(titles.used, width: .fixed(widths.used)) { row in
        Text(row.used)
          .foregroundStyle(ink(row.use).color)
      },
      DataColumn(titles.cost, width: .fixed(widths.cost), alignment: .trailing) { $0.cost },
    ]
  }
}
