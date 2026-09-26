import CoreGraphics
import Testing

@testable import ScopeUI

@Suite("the drawn mark matches its geometry", .serialized)
@MainActor
struct StatusBarsPixelTests {
  private let ink = ThemeLoader.pick(ThemeLoader.bundled(), for: .dark).text.primary

  private func alphas(_ image: CGImage) throws -> [[Double]] {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(
      CGContext(
        data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (0..<height).map { row in
      (0..<width).map { column in Double(bytes[(row * width + column) * 4 + 3]) / 255 }
    }
  }

  private func inside(_ point: CGPoint, _ part: StatusGlyph.Part) -> Bool {
    let rect = part.rect
    let radius = part.cornerRadius
    guard
      point.x >= rect.minX, point.x <= rect.maxX, point.y >= rect.minY, point.y <= rect.maxY
    else { return false }
    let dx = max(rect.minX + radius - point.x, 0, point.x - rect.maxX + radius)
    let dy = max(rect.minY + radius - point.y, 0, point.y - rect.maxY + radius)
    return dx == 0 || dy == 0 || hypot(dx, dy) <= radius - 0.05
  }

  private func covers(_ square: CGRect, _ part: StatusGlyph.Part) -> Bool {
    [
      CGPoint(x: square.minX, y: square.minY), CGPoint(x: square.maxX, y: square.minY),
      CGPoint(x: square.minX, y: square.maxY), CGPoint(x: square.maxX, y: square.maxY),
    ].allSatisfy { inside($0, part) }
  }

  private func misses(_ square: CGRect, _ part: StatusGlyph.Part) -> Bool {
    square.maxX <= part.rect.minX || square.minX >= part.rect.maxX
      || square.maxY <= part.rect.minY || square.minY >= part.rect.maxY
  }

  @Test(
    "every pixel wholly inside or outside each part has the parts' alpha",
    arguments: [CGFloat(1), 2])
  func alphasMatch(scale: CGFloat) throws {
    for state in StatusGlyph.State.allCases {
      for fill in [0, 0.44, 0.5, 1] {
        let face = StatusFace(state: state, fill: fill, number: nil)
        let image = try #require(StatusRender.image(face, ink: ink, scale: scale))
        #expect(image.width == Int(StatusGlyph.size.width * scale))
        #expect(image.height == Int(StatusGlyph.size.height * scale))
        let drawn = try alphas(image)
        let parts = StatusGlyph.parts(fill: face.fill, state: state)
        var checked = 0
        var seen = Set<Int>()
        for row in 0..<image.height {
          for column in 0..<image.width {
            let square = CGRect(
              x: CGFloat(column) / scale, y: CGFloat(row) / scale, width: 1 / scale,
              height: 1 / scale)
            let covering = parts.indices.filter { covers(square, parts[$0]) }
            let clean = parts.indices.allSatisfy {
              covering.contains($0) || misses(square, parts[$0])
            }
            guard clean else { continue }
            let alpha = covering.reduce(0.0) { total, index in
              total + parts[index].alpha * (1 - total)
            }
            let expected = alpha * StatusGlyph.opacity(state)
            // Corner curves antialias a few levels into the pixels beside them.
            #expect(
              abs(drawn[row][column] - expected) < 16 / 255,
              "\(state) at \(fill), \(scale)x, pixel \(column),\(row)")
            checked += 1
            seen.formUnion(covering)
          }
        }
        #expect(checked > image.width * image.height / 2)
        if scale == 2 {
          #expect(seen == Set(parts.indices), "\(state) at \(fill): every part is seen")
        }
      }
    }
  }
}
