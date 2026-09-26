import AppKit
import ScopeUI

@MainActor
enum StatusImage {
  // Every scale, not only the main display's: a bar on another display may use another.
  static func make(_ face: StatusFace, ink: ThemeColor, screen: NSScreen?) -> NSImage? {
    let image = NSImage(size: StatusGlyph.size)
    for scale in scales(for: screen) {
      guard let drawn = StatusRender.image(face, ink: ink, scale: scale) else { continue }
      let representation = NSBitmapImageRep(cgImage: drawn)
      representation.size = StatusGlyph.size
      image.addRepresentation(representation)
    }
    guard !image.representations.isEmpty else { return nil }
    image.isTemplate = true
    return image
  }

  static func scales(for screen: NSScreen?) -> [CGFloat] {
    let standard: [CGFloat] = [1, 2]
    guard let scale = screen?.backingScaleFactor, scale > 0, !standard.contains(scale) else {
      return standard
    }
    return (standard + [scale]).sorted()
  }
}
