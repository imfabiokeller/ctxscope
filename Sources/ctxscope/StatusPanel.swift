import AppKit
import ScopeUI
import SwiftUI

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

  // A borderless panel cannot become key without this override.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor
final class StatusPanel {
  private let window = PanelWindow()
  private let host: NSHostingController<AnyView>
  private let margins: PanelPlacement.Margins
  private let metrics: Metrics.Popover
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
    // The window is sized in `place()`, never by the hosting view.
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
        // Deferred: resizing the window inside its own layout pass re-enters layout.
        .onGeometryChange(for: CGSize.self, of: \.size) { [weak self] _ in
          Task { @MainActor in self?.place() }
        })
  }

  var isShown: Bool { window.isVisible }

  // Asks the content: with no sizing options the hosting view reports a zero fitting size.
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

  func close() {
    guard window.isVisible || !monitors.isEmpty else { return }
    for monitor in monitors { NSEvent.removeMonitor(monitor) }
    monitors = []
    if let resignToken { NotificationCenter.default.removeObserver(resignToken) }
    resignToken = nil
    window.orderOut(nil)
    onClose?()
  }

  private func place() {
    guard let item, let screen = item.screen ?? NSScreen.main else { return }
    let size = panelSize
    let placement = PanelPlacement.place(
      size, under: item.frame, on: screen.visibleFrame, margins: margins, gap: metrics.gap,
      inset: metrics.screenInset)
    window.setFrame(placement.window, display: true)
  }

  static let escapeKey: UInt16 = 53

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
    // A local monitor rather than `cancelOperation`: activation can hand the keyboard
    // to another of our windows after the panel is made key.
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

  private func isOutside(_ event: NSEvent) -> Bool {
    guard let clicked = event.window else { return true }
    if clicked === item { return false }
    guard clicked === window else { return true }
    let panel = window.contentLayoutRect.inset(by: margins)
    return !panel.contains(event.locationInWindow)
  }
}

extension CGRect {
  fileprivate func inset(by margins: PanelPlacement.Margins) -> CGRect {
    CGRect(
      x: minX + margins.side, y: minY + margins.bottom,
      width: width - 2 * margins.side, height: height - margins.top - margins.bottom)
  }
}
