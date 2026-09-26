import ScopeUI
import SwiftUI

struct ComponentGallery: View {
  static let size = CGSize(width: 1440, height: 1180)
  private static let controlsWidth: CGFloat = 620

  @Environment(\.theme) private var theme

  var body: some View {
    let card = theme.metrics.card
    HStack(alignment: .top, spacing: card.gap * 3) {
      VStack(alignment: .leading, spacing: card.gap * 2) {
        ControlsSection()
        StatusSection()
        SurfacesSection()
      }
      .frame(width: Self.controlsWidth)
      VStack(alignment: .leading, spacing: card.gap * 2) {
        TablesSection()
        ListsSection()
      }
      .frame(maxWidth: .infinity)
    }
    .padding(card.gap * 2)
    .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    .background(theme.surface.window.color)
  }
}

struct GallerySection<Content: View>: View {
  let title: String
  let content: Content
  @Environment(\.theme) private var theme

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: theme.metrics.table.cellPadding) {
      SectionHeader(title)
      content
    }
  }
}

struct GalleryRow<Content: View>: View {
  let label: String
  let content: Content
  @Environment(\.theme) private var theme
  private static var labelWidth: CGFloat { 130 }

  init(_ label: String, @ViewBuilder content: () -> Content) {
    self.label = label
    self.content = content()
  }

  var body: some View {
    HStack(spacing: theme.metrics.table.columnGap) {
      Text(label).font(theme.type.caption).foregroundStyle(theme.text.secondary.color)
        .frame(width: Self.labelWidth, alignment: .leading)
      content
    }
  }
}

private struct ControlsSection: View {
  @Environment(\.theme) private var theme

  var body: some View {
    let gap = theme.metrics.header.gap
    GallerySection("Controls") {
      GalleryRow("Pop-up buttons") {
        ToolbarPopUpButton(title: "retry-policy", subtitle: "~/code/api-client", emphasized: true) {
          Button("retry-policy") {}
        }
        ToolbarPopUpButton(title: "Lane: main", subtitle: "+ 2 subagents") {
          Button("Main") {}
        }
      }
      GalleryRow("View picker") {
        SegmentedPicker(
          "View", selection: .constant(WindowPage.context), options: WindowPage.allCases,
          title: \.rawValue)
        SegmentedPicker(
          "View", selection: .constant(WindowPage.timeline), options: WindowPage.allCases,
          title: \.rawValue)
      }
      GalleryRow("Filter picker") {
        SegmentedPicker(
          "Show", selection: .constant("All"), options: ["All", "Unused", "Sent every request"],
          size: .filter
        ) { $0 }
      }
      GalleryRow("Stepper") {
        HStack(spacing: gap) {
          RequestStepper(position: 87, count: 87, onPrevious: {}, onNext: {})
          RequestStepper(position: 1, count: 87, onPrevious: {}, onNext: {})
        }
      }
      GalleryRow("Search field") {
        SearchField("Filter blocks", text: .constant(""))
        SearchField("Filter blocks", text: .constant("npm test"))
      }
      GalleryRow("Push buttons") {
        Button("Show in timeline") {}.buttonStyle(.borderedPush)
        Button("Copy") {}.buttonStyle(.borderedPush(.tall))
        Button("Disabled") {}.buttonStyle(.borderedPush).disabled(true)
        Button {
        } label: {
          GlyphView(.ellipsis, side: theme.metrics.control.ellipsis)
        }
        .buttonStyle(.iconPush)
        .accessibilityLabel("More")
      }
      GalleryRow("Primary, links") {
        Button {
        } label: {
          Text("Open window").frame(width: theme.metrics.window.sidebarWidth / 2)
        }
        .buttonStyle(.primaryPush)
        Button("Show context at request 63") {}.buttonStyle(.textLink)
        Button("Quit ctxscope") {}.buttonStyle(.textLink(.plain))
      }
    }
  }
}

private struct StatusSection: View {
  @Environment(\.theme) private var theme

  var body: some View {
    GallerySection("Status and kinds") {
      GalleryRow("Live") {
        LivePill()
        StatusDot()
        HeaderNote("87 requests · $3.94")
      }
      GalleryRow("Badges") {
        NumberBadge(1)
        NumberBadge(2)
        NumberBadge(3)
        NumberBadge(12)
      }
      GalleryRow("Swatches") {
        ForEach(theme.kind.named, id: \.name) { kind in
          VStack(spacing: theme.metrics.swatch.legendGap) {
            KindSwatch(kind.color, size: .legend)
            KindSwatch(kind.color, size: .table)
            KindSwatch(kind.color, size: .compact)
          }
        }
      }
      GalleryRow("Legend, detailed") {
        legend(.detailed, detail: "3.1k · 2%")
      }
      GalleryRow("Legend, plain") {
        legend(.plain, detail: nil)
      }
      GalleryRow("Legend, compact") {
        legend(.compact, detail: "3.1k")
      }
      GalleryRow("Kind labels") {
        KindLegendItem(color: theme.kind.results, name: "results", style: .table)
        KindLegendItem(color: theme.kind.results, name: "results", style: .caption)
      }
    }
  }

  private func legend(_ style: KindLegendItem.Style, detail: String?) -> some View {
    HStack(spacing: theme.metrics.header.gap) {
      ForEach(theme.kind.named.prefix(4), id: \.name) { kind in
        KindLegendItem(color: kind.color, name: kind.name, detail: detail, style: style)
      }
    }
  }
}
