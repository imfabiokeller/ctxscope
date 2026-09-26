public import SwiftUI

public struct DataColumn<Row> {
  public enum Width: Sendable {
    case fixed(CGFloat)
    case flexible
  }

  let title: String
  let width: Width
  let alignment: Alignment
  let cell: (Row) -> AnyView

  public init<Cell: View>(
    _ title: String, width: Width = .flexible, alignment: HorizontalAlignment = .leading,
    @ViewBuilder cell: @escaping (Row) -> Cell
  ) {
    self.title = title
    self.width = width
    self.alignment = alignment == .trailing ? .trailing : .leading
    self.cell = { AnyView(cell($0)) }
  }

  public init(
    _ title: String, width: Width = .flexible, alignment: HorizontalAlignment = .leading,
    text: @escaping (Row) -> String
  ) {
    self.init(title, width: width, alignment: alignment) { row in Text(text(row)) }
  }
}

extension View {
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
