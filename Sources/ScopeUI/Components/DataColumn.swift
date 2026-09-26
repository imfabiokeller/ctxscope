public import SwiftUI

/// One column of a `DataTable`: its title, how wide it is, which side its
/// cells hold to, and how a row fills its cell.
public struct DataColumn<Row> {
  public enum Width: Sendable {
    case fixed(CGFloat)
    /// Takes what the fixed columns leave. Each table has one such column;
    /// more would share the room evenly.
    case flexible
  }

  let title: String
  let width: Width
  let alignment: Alignment
  let cell: (Row) -> AnyView

  /// `alignment` is `.leading` or `.trailing`: numbers hold to the right so
  /// their digits line up.
  public init<Cell: View>(
    _ title: String, width: Width = .flexible, alignment: HorizontalAlignment = .leading,
    @ViewBuilder cell: @escaping (Row) -> Cell
  ) {
    self.title = title
    self.width = width
    self.alignment = alignment == .trailing ? .trailing : .leading
    self.cell = { AnyView(cell($0)) }
  }

  /// A column whose cell is one line of text.
  public init(
    _ title: String, width: Width = .flexible, alignment: HorizontalAlignment = .leading,
    text: @escaping (Row) -> String
  ) {
    self.init(title, width: width, alignment: alignment) { row in Text(text(row)) }
  }
}

extension View {
  /// Sizes a cell or a header title to its column.
  @ViewBuilder
  func column<Row>(_ column: DataColumn<Row>) -> some View {
    switch column.width {
    case .fixed(let width):
      frame(width: width, alignment: column.alignment)
    case .flexible:
      frame(maxWidth: .infinity, alignment: column.alignment)
    }
  }
}
