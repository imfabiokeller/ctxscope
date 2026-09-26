public import SwiftUI

/// A table of rows with a header, one selected row, and selection by click
/// and by the up and down arrows.
///
/// Rows are laid out lazily, so a table of a few thousand blocks costs what
/// its visible rows cost. SwiftUI's own `Table` would bring the system's
/// header, row height and selection color, none of which is the theme's.
/// Each row is a native button, so a click selects it and accessibility
/// reads it as one element with its selected state.
public struct DataTable<Row: Identifiable>: View {
  public enum Density: Sendable {
    /// A 28 point header and 30 point rows: the blocks table.
    case regular
    /// A 26 point header and 28 point rows: the prompts table.
    case compact
  }

  private let rows: [Row]
  @Binding private var selection: Row.ID?
  private let density: Density
  private let columns: [DataColumn<Row>]
  @FocusState private var isFocused: Bool
  @Environment(\.theme) private var theme
  @Environment(\.isRendering) private var isRendering

  public init(
    _ rows: [Row], selection: Binding<Row.ID?>, density: Density = .regular,
    columns: [DataColumn<Row>]
  ) {
    self.rows = rows
    _selection = selection
    self.density = density
    self.columns = columns
  }

  public var body: some View {
    VStack(spacing: 0) {
      Hairline()
      header
      Hairline()
      // A scroll view renders as an empty box offscreen, so under the
      // renderer the rows are laid out plainly and clipped to the table.
      if isRendering {
        VStack(spacing: 0) { rowViews }
          .frame(maxHeight: .infinity, alignment: .top)
          .clipped()
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 0) { rowViews }
          }
          .onChange(of: selection) { _, selected in
            guard let selected else { return }
            proxy.scrollTo(selected)
          }
        }
      }
    }
    .focusable()
    .focused($isFocused)
    .focusEffectDisabled()
    .onKeyPress(.upArrow) { move(by: -1) }
    .onKeyPress(.downArrow) { move(by: 1) }
  }

  private var table: Metrics.Table { theme.metrics.table }

  private var header: some View {
    cells { column in Text(column.title).lineLimit(1) }
      .font(theme.type.smallMedium)
      .foregroundStyle(theme.text.secondary.color)
      .frame(height: density == .regular ? table.headerHeight : table.compactHeaderHeight)
      .accessibilityAddTraits(.isHeader)
  }

  private var rowViews: some View {
    ForEach(rows) { row in
      let isSelected = row.id == selection
      Button {
        selection = row.id
        isFocused = true
      } label: {
        VStack(spacing: 0) {
          cells { column in column.cell(row).lineLimit(1).truncationMode(.tail) }
            .frame(maxHeight: .infinity)
          Hairline(.row)
        }
        .frame(height: density == .regular ? table.rowHeight : table.compactRowHeight)
        .background(isSelected ? theme.surface.selection.color : nil)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    .font(theme.type.body)
    .foregroundStyle(theme.text.primary.color)
  }

  /// One cell per column, spaced and inset the way every row and the header
  /// are.
  private func cells(
    @ViewBuilder _ content: @escaping (DataColumn<Row>) -> some View
  ) -> some View {
    HStack(spacing: table.columnGap) {
      ForEach(columns.indices, id: \.self) { index in
        content(columns[index]).column(columns[index])
      }
    }
    .padding(.horizontal, table.cellPadding)
  }

  /// Moves the selection one row up or down, and starts at the top when
  /// nothing is selected yet.
  private func move(by step: Int) -> KeyPress.Result {
    guard !rows.isEmpty else { return .ignored }
    let current = selection.flatMap { id in rows.firstIndex { $0.id == id } }
    let next = current.map { min(rows.count - 1, max(0, $0 + step)) } ?? 0
    selection = rows[next].id
    return .handled
  }
}

#Preview {
  struct Block: Identifiable {
    let id: Int
    let label: String
    let size: String
  }
  @Previewable @State var selection: Int? = 0
  let rows = (0..<2000).map { Block(id: $0, label: "Read · src/file\($0).ts", size: "~1.2k") }
  return DataTable(
    rows, selection: $selection,
    columns: [
      DataColumn("Block") { $0.label },
      DataColumn(
        "Size", width: .fixed(Theme.preview.metrics.table.blocks.size), alignment: .trailing
      ) { $0.size },
    ]
  )
  .frame(width: 500, height: 300)
  .environment(\.theme, Theme.preview)
}
