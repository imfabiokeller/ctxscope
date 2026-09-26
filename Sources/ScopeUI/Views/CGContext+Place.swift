internal import CoreGraphics

extension CGContext {
  /// Flips the rect, since SwiftUI's context runs y down and a bitmap does not.
  /// No smoothing: interpolation would smear column boundaries.
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
