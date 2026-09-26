internal import CoreGraphics

extension CGContext {
  /// Puts an image into a rectangle of a context whose y runs down, which is
  /// what SwiftUI hands over and what a plain Core Graphics bitmap is not. The
  /// rectangle is flipped around for the draw and put back afterwards, or the
  /// picture comes out standing on its head.
  ///
  /// Nothing is smoothed: a chart's image is either at the display's pixels
  /// or in request space, and interpolating either turns a column boundary
  /// into a smear.
  func place(_ image: CGImage, in rect: CGRect) {
    saveGState()
    interpolationQuality = .none
    setShouldAntialias(false)
    translateBy(x: 0, y: rect.maxY)
    scaleBy(x: 1, y: -1)
    draw(image, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
    restoreGState()
  }
}
