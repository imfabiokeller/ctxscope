import AppKit
import Foundation
import SwiftUI

/// Renders a view to a PNG without a window.
///
/// The files have to be producible from a command line: no window server
/// session, no screen capture permission, no app running.
@MainActor
enum Renderer {
  /// Rendered at two device pixels per point, which is what the display these
  /// are checked on shows.
  static let scale: CGFloat = 2

  static func write(_ view: some View, size: CGSize, to url: URL) -> URL? {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = scale
    renderer.isOpaque = true
    guard let image = renderer.cgImage,
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { return nil }
    try? data.write(to: url)
    return url
  }

  /// Renders a view the way a window lays it out, scroll views and all, by
  /// hosting it in a window that is never shown and drawing its layer. What
  /// a window draws off the main actor, such as the timeline's columns, is
  /// given time to arrive.
  static func writeHosted(_ view: some View, size: CGSize, to url: URL) async -> URL? {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    host.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(
      contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    try? await Task.sleep(for: .seconds(2))
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { return nil }
    try? data.write(to: url)
    return url
  }
}

/// The few flags the renderer takes.
enum Arguments {
  static func value(_ name: String) -> String? {
    let flag = "--\(name)"
    let arguments = CommandLine.arguments
    guard let slot = arguments.firstIndex(of: flag), slot + 1 < arguments.count else {
      return nil
    }
    return arguments[slot + 1]
  }

  /// Whether a flag that takes no value was given.
  static func flag(_ name: String) -> Bool {
    CommandLine.arguments.contains("--\(name)")
  }
}
