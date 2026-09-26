public import SwiftUI

/// A section's title, with a detail line and anything the section needs to
/// control beside it.
public struct SectionHeader<Accessory: View>: View {
  public enum Layout: Sendable {
    /// The detail at the far end, on the title's baseline: "Context in
    /// reading order ... 0 → 200k tokens".
    case spread
    /// The detail right after the title, and the accessory at the far end:
    /// "Blocks 1,284 in this request ... [All | Unused] [Filter]".
    case inline
  }

  public enum Tone: Sendable {
    case secondary
    /// A step darker, for a detail that carries a figure.
    case supporting
  }

  private let title: String
  private let detail: Text?
  private let tone: Tone
  private let layout: Layout
  private let accessory: Accessory
  @Environment(\.theme) private var theme

  /// The detail is a `Text` so a caller can set a figure in it in a stronger
  /// weight. Anything it does not style itself is set in the caption size.
  public init(
    _ title: String, detail: Text? = nil, tone: Tone = .secondary, layout: Layout = .spread,
    @ViewBuilder accessory: () -> Accessory
  ) {
    self.title = title
    self.detail = detail
    self.tone = tone
    self.layout = layout
    self.accessory = accessory()
  }

  public var body: some View {
    switch layout {
    case .spread:
      HStack(alignment: .firstTextBaseline, spacing: theme.metrics.header.gap) {
        heading
        Spacer(minLength: 0)
        detailText
        accessory
      }
      .line(theme.type.lines.body)
    case .inline:
      HStack(spacing: theme.metrics.table.columnGap) {
        heading
        detailText
        Spacer(minLength: 0)
        accessory
      }
    }
  }

  private var heading: some View {
    Text(title)
      .font(theme.type.bodyStrong)
      .foregroundStyle(theme.text.primary.color)
      .accessibilityAddTraits(.isHeader)
  }

  @ViewBuilder private var detailText: some View {
    if let detail {
      detail
        .font(theme.type.caption)
        .foregroundStyle((tone == .secondary ? theme.text.secondary : theme.text.supporting).color)
        .lineLimit(1)
    }
  }
}

extension SectionHeader where Accessory == EmptyView {
  public init(
    _ title: String, detail: Text? = nil, tone: Tone = .secondary, layout: Layout = .spread
  ) {
    self.init(title, detail: detail, tone: tone, layout: layout) { EmptyView() }
  }
}

#Preview {
  VStack(spacing: 20) {
    SectionHeader("Context in reading order", detail: Text("0 → 200k tokens"))
    SectionHeader(
      "Blocks", detail: Text("1,284 in this request · largest first"), layout: .inline
    ) {
      Button("Filter") {}.buttonStyle(.borderedPush)
    }
  }
  .frame(width: 600)
  .padding()
  .environment(\.theme, Theme.preview)
}
