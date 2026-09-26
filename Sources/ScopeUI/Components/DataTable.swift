public import SwiftUI

public struct DataTable<Row: Identifiable>: View {
  public enum Density: Sendable {
    case regular
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
      // A scroll view renders as an empty box offscreen.
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
