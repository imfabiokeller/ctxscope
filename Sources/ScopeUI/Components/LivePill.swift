public import SwiftUI

/// Says that the session is being written to right now: a green dot and a
/// word in a pill, in the window's header.
public struct LivePill: View {
  private let title: String
  @Environment(\.theme) private var theme

  public init(_ title: String = "Live") {
    self.title = title
  }

  public var body: some View {
    let pill = theme.metrics.pill
    HStack(spacing: pill.gap) {
      Circle().fill(theme.status.liveDot.color).frame(width: pill.dot, height: pill.dot)
      Text(title).font(theme.type.captionMedium).foregroundStyle(theme.status.liveInk.color)
    }
    .padding(.horizontal, pill.padding)
    .frame(height: pill.height)
    .background(Capsule().fill(theme.status.liveFill.color))
    .accessibilityElement(children: .combine)
  }
}

/// The same statement without the pill, where there is less room: the
/// popover's first line.
public struct StatusDot: View {
  private let title: String
  @Environment(\.theme) private var theme

  public init(_ title: String = "Live") {
    self.title = title
  }

  public var body: some View {
    let pill = theme.metrics.pill
    HStack(spacing: pill.statusGap) {
      Circle().fill(theme.status.liveDot.color)
        .frame(width: pill.statusDot, height: pill.statusDot)
      Text(title).font(theme.type.smallMedium).foregroundStyle(theme.status.liveInk.color)
    }
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  HStack(spacing: 16) {
    LivePill()
    StatusDot()
  }
  .padding()
  .environment(\.theme, Theme.preview)
}
