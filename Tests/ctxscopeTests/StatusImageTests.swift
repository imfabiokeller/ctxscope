import AppKit
import ScopeCore
import ScopeUI
import Testing

@testable import ctxscope

@Suite("the image in the bar", .serialized)
@MainActor
struct StatusImageTests {
  private var ink: ThemeColor { ThemeLoader.pick(ThemeLoader.bundled(), for: .dark).text.primary }

  private func face(isLive: Bool?) -> StatusFace {
    StatusFace(
      reading: isLive.map { StatusReading(isLive: $0, totalTokens: 142_600, window: 200_000) })
  }

  @Test("it carries a 1x and a 2x representation, measured in points")
  func representations() throws {
    let image = try #require(StatusImage.make(face(isLive: true), ink: ink, screen: nil))
    #expect(image.size == StatusGlyph.size)
    let reps = image.representations.compactMap { $0 as? NSBitmapImageRep }
    #expect(reps.count == 2)
    #expect(reps.allSatisfy { $0.size == StatusGlyph.size })
    let widths = Set(reps.map(\.pixelsWide)).sorted()
    #expect(widths == [Int(StatusGlyph.size.width), Int(StatusGlyph.size.width * 2)])
    let png = { (rep: NSBitmapImageRep) in rep.representation(using: .png, properties: [:]) }
    #expect(png(reps[0]) != png(reps[1]))
  }

  @Test("a bar with a scale of its own gets a representation for it")
  func scales() {
    #expect(StatusImage.scales(for: nil) == [1, 2])
    for screen in NSScreen.screens {
      #expect(StatusImage.scales(for: screen).contains(screen.backingScaleFactor))
      #expect(StatusImage.scales(for: screen).contains(1))
      #expect(StatusImage.scales(for: screen).contains(2))
    }
  }

  @Test("every state is a template, so the bar inverts it")
  func templates() throws {
    for isLive in [true, false, nil] {
      let image = try #require(StatusImage.make(face(isLive: isLive), ink: ink, screen: nil))
      #expect(image.isTemplate)
    }
  }

  @Test("filled, dimmed and outlined are three different pictures")
  func states() throws {
    let pixels = { (face: StatusFace) -> Data? in
      StatusImage.make(face, ink: self.ink, screen: nil)?.tiffRepresentation
    }
    let drawn = [face(isLive: true), face(isLive: false), face(isLive: nil)].map(pixels)
    #expect(Set(drawn.compactMap { $0 }).count == 3)
  }
}
