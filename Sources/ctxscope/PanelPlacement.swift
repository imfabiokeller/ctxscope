import Foundation

struct PanelPlacement: Equatable {
  struct Margins: Equatable {
    var top: CGFloat
    var side: CGFloat
    var bottom: CGFloat
  }

  let panel: CGRect
  let window: CGRect
  let margins: Margins

  // The top margin is capped at the gap so the window never covers the menu bar items.
  static func margins(reach: Margins, gap: CGFloat) -> Margins {
    Margins(top: min(reach.top, gap), side: reach.side, bottom: reach.bottom)
  }

  static func place(
    _ size: CGSize, under item: CGRect, on screen: CGRect, margins: Margins, gap: CGFloat,
    inset: CGFloat
  ) -> PanelPlacement {
    let lowest = screen.minX + inset
    let highest = max(lowest, screen.maxX - inset - size.width)
    let x = min(highest, max(lowest, item.midX - size.width / 2))
    let panel = CGRect(
      x: x, y: item.minY - gap - size.height, width: size.width, height: size.height)
    let window = CGRect(
      x: panel.minX - margins.side,
      y: panel.minY - margins.bottom,
      width: panel.width + 2 * margins.side,
      height: panel.height + margins.top + margins.bottom)
    return PanelPlacement(panel: panel, window: window, margins: margins)
  }
}
