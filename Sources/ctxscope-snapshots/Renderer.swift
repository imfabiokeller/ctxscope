import AppKit
import Foundation
import SwiftUI

// Must run from a command line: no window server session, no screen capture permission.
@MainActor
enum Renderer {
  // Two pixels per point, as on the display the pictures are checked on.
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

  // The wait gives what a window draws off the main actor (the timeline's columns) time to arrive.
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

enum Arguments {
  static func value(_ name: String) -> String? {
    let flag = "--\(name)"
    let arguments = CommandLine.arguments
    guard let slot = arguments.firstIndex(of: flag), slot + 1 < arguments.count else {
      return nil
    }
    return arguments[slot + 1]
  }

  static func flag(_ name: String) -> Bool {
    CommandLine.arguments.contains("--\(name)")
  }
}
