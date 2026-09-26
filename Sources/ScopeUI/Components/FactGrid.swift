public import SwiftUI

/// One fact on a solid tile, the prompt bands' look: a small label, the value
/// on one line, and a quieter line under it when there is more to say. A
/// fact about a block can lead with its kind's swatch and end with a figure.
public struct FactTile: View {
  private let label: String
  private let value: String
  private let detail: String?
  private let swatch: ThemeColor?
  private let trailing: String?
  @Environment(\.theme) private var theme

  public init(
    label: String, value: String, detail: String? = nil, swatch: ThemeColor? = nil,
    trailing: String? = nil
  ) {
    self.label = label
    self.value = value
    self.detail = detail
    self.swatch = swatch
    self.trailing = trailing
  }

  public var body: some View {
    let tile = theme.metrics.tile
    let type = theme.type
    VStack(alignment: .leading, spacing: 0) {
      Text(label).font(type.smallMedium).foregroundStyle(theme.text.secondary.color)
        .lineLimit(1)
        .line(type.lines.small)
        .padding(.bottom, tile.labelGap)
      HStack(spacing: tile.valueGap) {
        if let swatch { KindSwatch(swatch) }
        // A value never wraps: a long one loses its middle, where a path's
        // folders are, and keeps both ends.
        Text(value).font(type.heading).foregroundStyle(theme.text.primary.color)
          .lineLimit(1).truncationMode(.middle)
          .layoutPriority(1)
        if let trailing {
          Spacer(minLength: 0)
          Text(trailing).font(type.bodyMedium).foregroundStyle(theme.text.secondary.color)
            .lineLimit(1).fixedSize()
        }
      }
      .line(type.lines.heading)
      if let detail {
        Text(detail).font(type.small).foregroundStyle(theme.text.secondary.color)
          .lineLimit(1).truncationMode(.middle)
          .line(type.lines.small)
          .padding(.top, tile.detailGap)
      }
    }
    .padding(tile.padding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: tile.radius).fill(theme.surface.tile.color))
    .accessibilityElement(children: .combine)
  }
}

/// Facts on tiles two to a row, a wide one on a row of its own. The tiles
/// of a row are as tall as the taller of them.
public struct FactGrid<Item: Identifiable, Tile: View>: View {
  private let items: [Item]
  private let isWide: (Item) -> Bool
  private let tile: (Item) -> Tile
  @Environment(\.theme) private var theme

  public init(
    _ items: [Item], isWide: @escaping (Item) -> Bool,
    @ViewBuilder tile: @escaping (Item) -> Tile
  ) {
    self.items = items
    self.isWide = isWide
    self.tile = tile
  }

  public var body: some View {
    let gap = theme.metrics.tile.gap
    VStack(spacing: gap) {
      ForEach(Self.rows(of: items.count) { isWide(items[$0]) }, id: \.self) { row in
        HStack(alignment: .top, spacing: gap) {
          ForEach(row, id: \.self) { tile(items[$0]) }
          // A narrow tile alone on its row keeps a narrow tile's width.
          if row.count == 1, !isWide(items[row[0]]) { Spacer().frame(maxWidth: .infinity) }
        }
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  /// The items' positions, row by row: a wide item alone, narrow ones in
  /// pairs in the order they come.
  nonisolated static func rows(of count: Int, isWide: (Int) -> Bool) -> [[Int]] {
    var rows: [[Int]] = []
    var pending: Int?
    for index in 0..<count {
      if isWide(index) {
        if let open = pending { rows.append([open]) }
        pending = nil
        rows.append([index])
      } else if let open = pending {
        rows.append([open, index])
        pending = nil
      } else {
        pending = index
      }
    }
    if let open = pending { rows.append([open]) }
    return rows
  }
}
