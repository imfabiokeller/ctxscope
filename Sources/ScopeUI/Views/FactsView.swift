internal import SwiftUI

/// A sidebar's facts on their tiles, a kind's swatch in its theme color.
struct FactsView: View {
  let facts: [FactData]
  @Environment(\.theme) private var theme

  var body: some View {
    FactGrid(facts, isWide: \.isWide) { fact in
      FactTile(
        label: fact.term, value: fact.value, detail: fact.detail,
        swatch: fact.swatch.map { theme.color(of: $0.kind) }, trailing: fact.trailing)
    }
  }
}
