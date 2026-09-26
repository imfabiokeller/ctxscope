public import SwiftUI

public struct PopUpTitle: Sendable, Hashable {
  public let title: String
  public let subtitle: String?
  public let emphasized: Bool

  public init(_ title: String, subtitle: String? = nil, emphasized: Bool = false) {
    self.title = title
    self.subtitle = subtitle
    self.emphasized = emphasized
  }
}

// The leading space is left for the traffic lights, which the system draws over the bar.
public struct WindowHeader<
  Page: Hashable, SessionItems: View, LaneItems: View, Trailing: View
>: View {
  private let session: PopUpTitle
  private let sessionItems: SessionItems
  private let lane: PopUpTitle
  private let laneItems: LaneItems
  private let pages: [Page]
  @Binding private var page: Page
  private let pageTitle: (Page) -> String
  private let liveTitle: String?
  private let trailing: Trailing
  @Environment(\.theme) private var theme

  public init(
    session: PopUpTitle, @ViewBuilder sessionItems: () -> SessionItems,
    lane: PopUpTitle, @ViewBuilder laneItems: () -> LaneItems,
    pages: [Page], page: Binding<Page>, pageTitle: @escaping (Page) -> String,
    liveTitle: String?, @ViewBuilder trailing: () -> Trailing
  ) {
    self.session = session
    self.sessionItems = sessionItems()
    self.lane = lane
    self.laneItems = laneItems()
    self.pages = pages
    _page = page
    self.pageTitle = pageTitle
    self.liveTitle = liveTitle
    self.trailing = trailing()
  }

  public var body: some View {
    let header = theme.metrics.header
    VStack(spacing: 0) {
      HStack(spacing: header.gap) {
        Spacer(minLength: 0).frame(width: header.trafficLightReserve)
        ToolbarPopUpButton(
          title: session.title, subtitle: session.subtitle, emphasized: session.emphasized
        ) { sessionItems }
        ToolbarPopUpButton(
          title: lane.title, subtitle: lane.subtitle, emphasized: lane.emphasized
        ) { laneItems }
        SegmentedPicker("View", selection: $page, options: pages, title: pageTitle)
          .padding(.leading, header.pickerLeading)
        Spacer(minLength: 0)
        trailing
        if let liveTitle {
          LivePill(liveTitle)
        }
      }
      .padding(.horizontal, header.padding)
      .frame(height: header.height)
      Hairline()
    }
    .background(theme.surface.header.color)
  }
}

public struct HeaderNote: View {
  private let text: String
  @Environment(\.theme) private var theme

  public init(_ text: String) {
    self.text = text
  }

  public var body: some View {
    Text(text)
      .font(theme.type.body)
      .foregroundStyle(theme.text.supporting.color)
      .lineLimit(1)
  }
}

#Preview {
  @Previewable @State var page = "Context"
  WindowHeader(
    session: PopUpTitle("retry-policy", subtitle: "~/code/api-client", emphasized: true),
    sessionItems: { Button("helm-chart-bump") {} },
    lane: PopUpTitle("Lane: main", subtitle: "+ 2 subagents"),
    laneItems: { Button("Main") {} },
    pages: ["Context", "Timeline"], page: $page, pageTitle: { $0 },
    liveTitle: "Live"
  ) {
    RequestStepper(position: 87, count: 87, onPrevious: {}, onNext: {})
  }
  .frame(width: Theme.preview.metrics.window.size.width)
  .environment(\.theme, Theme.preview)
}
