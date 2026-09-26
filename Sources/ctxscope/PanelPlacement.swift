import Foundation

/// Where the popover's panel goes on screen, and the window around it.
///
/// The panel hangs under the status item, centered on it, a few points below
/// the bar, and kept a few points inside the screen's edges. The window it
/// sits in is larger than the panel by the reach of the panel's shadow on
/// every side but the top, where it stops at the bar so it never covers the
/// items there, the status item included.
///
/// Pure geometry in AppKit's screen coordinates, with y growing upwards, so
/// it is decided in a test rather than on a screen.
struct PanelPlacement: Equatable {
  /// Room around the panel inside its window.
  struct Margins: Equatable {
    var top: CGFloat
    var side: CGFloat
    var bottom: CGFloat
  }

  /// The panel itself, border included.
  let panel: CGRect
  /// The window: the panel and the room its shadow takes.
  let window: CGRect
  let margins: Margins

  /// The room the window leaves around the panel: the shadow's reach, except
  /// above, where the window stops at the bar.
  static func margins(reach: Margins, gap: CGFloat) -> Margins {
    Margins(top: min(reach.top, gap), side: reach.side, bottom: reach.bottom)
  }

  /// - Parameters:
  ///   - size: the panel's size, border included.
  ///   - item: the status item's frame; its bottom edge is the bar's.
  ///   - screen: the visible frame of the screen the item is on.
  ///   - margins: the room around the panel, from `margins(reach:gap:)`.
  ///   - gap: from the bar to the panel.
  ///   - inset: the least room kept to the screen's edges.
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
