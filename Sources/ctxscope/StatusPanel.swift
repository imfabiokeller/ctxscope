import AppKit
import ScopeUI
import SwiftUI

/// The window the popover's panel sits in: borderless, clear, with no shadow
/// of its own, because the panel draws its corners, its border and its
/// shadow itself, the theme's and not the system's.
///
/// It can become key, which a borderless panel otherwise cannot, and it does
/// without activating ctxscope, so the keyboard reaches it while the
/// application that was in front stays in front.
final class PanelWindow: NSPanel {
  init() {
    super.init(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: true)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    level = .popUpMenu
    collectionBehavior = [.transient, .ignoresCycle, .moveToActiveSpace, .fullScreenAuxiliary]
    isReleasedWhenClosed = false
    hidesOnDeactivate = false
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

/// The popover, hung under the status item.
///
/// One hosting controller for as long as it is open: the content observes the
/// model and the theme, so a request landing redraws it rather than
/// rebuilding it, and a change of height moves the window's bottom edge and
/// keeps its top under the bar.
///
/// It closes on escape, on a click anywhere that is not the panel, and when
/// the application stops being active; whoever owns it is told once.
@MainActor
final class StatusPanel {
  private let window = PanelWindow()
  private let host: NSHostingController<AnyView>
  private let margins: PanelPlacement.Margins
  private let metrics: Metrics.Popover
  /// The status item's window: a click on it is the item's own toggle, not a
  /// click outside.
  private weak var item: NSWindow?
  private var monitors: [Any] = []
  private var resignToken: (any NSObjectProtocol)?
  var onClose: (() -> Void)?

  init(content: some View, theme: Theme) {
    let reach = theme.shadow.popover.reach
    metrics = theme.metrics.popover
    margins = PanelPlacement.margins(
      reach: PanelPlacement.Margins(top: reach.top, side: reach.horizontal, bottom: reach.bottom),
      gap: metrics.gap)
    host = NSHostingController(rootView: AnyView(EmptyView()))
    // The window's size is decided in `place()`, from what the content asks
    // for, so the hosting view never resizes the window on its own.
    host.sizingOptions = []
    window.contentViewController = host
    let margins = margins
    host.rootView = AnyView(
      content
        .padding(
          EdgeInsets(
            top: margins.top, leading: margins.side, bottom: margins.bottom,
            trailing: margins.side)
        )
        // After the layout pass that measured it, not inside it: a window
        // resized in the middle of laying out its own content lays it out
        // again from within.
        .onGeometryChange(for: CGSize.self, of: \.size) { [weak self] _ in
          Task { @MainActor in self?.place() }
        })
  }

  var isShown: Bool { window.isVisible }

  /// The panel's own size, border included, without the room around it.
  ///
  /// The content is asked directly. A hosting view that does not size its
  /// window has no fitting size to report, and a zero size put an empty box
  /// over the menu bar.
  var panelSize: CGSize {
    let fitting = host.sizeThatFits(
      in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
    return CGSize(
      width: fitting.width - 2 * margins.side,
      height: fitting.height - margins.top - margins.bottom)
  }

  func show(under item: NSWindow) {
    self.item = item
    place()
    window.makeKeyAndOrderFront(nil)
    watch()
  }

  /// Closes it, once. Whoever owns it hears about it from here, whatever
  /// closed it.
  func close() {
    guard window.isVisible || !monitors.isEmpty else { return }
    for monitor in monitors { NSEvent.removeMonitor(monitor) }
    monitors = []
    if let resignToken { NotificationCenter.default.removeObserver(resignToken) }
    resignToken = nil
    window.orderOut(nil)
    onClose?()
  }

  /// Puts the window where the panel belongs for the size the content has
  /// now.
  private func place() {
    guard let item, let screen = item.screen ?? NSScreen.main else { return }
    let size = panelSize
    let placement = PanelPlacement.place(
      size, under: item.frame, on: screen.visibleFrame, margins: margins, gap: metrics.gap,
      inset: metrics.screenInset)
    window.setFrame(placement.window, display: true)
  }

  /// The escape key's code.
  static let escapeKey: UInt16 = 53

  /// A click in another application, a click in one of ours that is not on
  /// the panel, escape, and the application stopping being active all close
  /// it.
  private func watch() {
    let others = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      Task { @MainActor in self?.close() }
    }
    let ours = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      guard let self else { return event }
      if isOutside(event) { close() }
      return event
    }
    // Escape closes it whichever of our windows is key. Activation finishes
    // after the panel is made key, and the window it activates takes the
    // keyboard back, so the panel's own `cancelOperation` alone missed it.
    let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, event.keyCode == Self.escapeKey else { return event }
      close()
      return nil
    }
    monitors = [others, ours, escape].compactMap { $0 }
    resignToken = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.close() }
    }
  }

  /// Whether a click in this application missed the panel: in another of
  /// its windows, or in the room the shadow takes around it. The item is
  /// neither, because a click there already toggles the panel.
  private func isOutside(_ event: NSEvent) -> Bool {
    guard let clicked = event.window else { return true }
    if clicked === item { return false }
    guard clicked === window else { return true }
    let panel = window.contentLayoutRect.inset(by: margins)
    return !panel.contains(event.locationInWindow)
  }
}

extension CGRect {
  /// The rect less the margins, in a view whose y grows upwards.
  fileprivate func inset(by margins: PanelPlacement.Margins) -> CGRect {
    CGRect(
      x: minX + margins.side, y: minY + margins.bottom,
      width: width - 2 * margins.side, height: height - margins.top - margins.bottom)
  }
}
