import AppKit
import ScopeUI

/// The mark, wrapped for the menu bar.
///
/// Always a template image, so the system inverts it with the bar, dims it
/// on a menu bar that is not in front, and highlights it when the item is
/// clicked. Only its alpha is ever drawn.
///
/// What is drawn is `StatusFace` and the drawing is `StatusRender`, both in
/// ScopeUI. Nothing here decides anything about how the item looks.
@MainActor
enum StatusImage {
  /// The image, carrying one representation per scale a bar can be shown at.
  ///
  /// Both scales, rather than the one the main display happens to have: a
  /// menu bar on a second display has its own, and an image drawn for the
  /// wrong one puts the half point edges between pixels.
  static func make(_ face: StatusFace, ink: ThemeColor, screen: NSScreen?) -> NSImage? {
    let image = NSImage(size: StatusGlyph.size)
    for scale in scales(for: screen) {
      guard let drawn = StatusRender.image(face, ink: ink, scale: scale) else { continue }
      let representation = NSBitmapImageRep(cgImage: drawn)
      // The pixels are at this scale and a representation is measured in
      // points, so the system picks the one that fits the bar it is drawing.
      representation.size = StatusGlyph.size
      image.addRepresentation(representation)
    }
    guard !image.representations.isEmpty else { return nil }
    image.isTemplate = true
    return image
  }

  /// The scales the image carries: the two a Mac display can have, plus the
  /// bar's own if it is ever anything else.
  static func scales(for screen: NSScreen?) -> [CGFloat] {
    let standard: [CGFloat] = [1, 2]
    guard let scale = screen?.backingScaleFactor, scale > 0, !standard.contains(scale) else {
      return standard
    }
    return (standard + [scale]).sorted()
  }
}
