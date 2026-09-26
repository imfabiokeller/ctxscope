import AppKit
import ScopeCore
import ScopeUI
import Testing

@testable import ctxscope

/// A bar to draw on that is not a bar.
@MainActor
private final class FakeButton: StatusButton {
  var barScreen: NSScreen? { nil }
  private(set) var draws = 0
  private(set) var fades = 0
  private(set) var image: NSImage?
  private(set) var number = ""
  private(set) var tooltip = ""
  private(set) var value = ""

  func crossFade(seconds: Double) {
    fades += 1
  }

  func draw(image: NSImage?, number: NSAttributedString, tooltip: String, value: String) {
    draws += 1
    self.image = image
    self.number = number.string
    self.tooltip = tooltip
    self.value = value
  }
}

/// What the item draws, and when it bothers.
@Suite("what the item draws", .serialized)
@MainActor
struct StatusItemTests {
  private func controller(live: Bool) async throws -> (StatusItemController, InstrumentModel) {
    let recording = SyntheticRecording.make()
    let model = InstrumentModel(feed: RecordingFeed(recordings: [recording]))
    model.reloadSessions()
    await model.settle()
    model.focus(session: recording.sessionID)
    await model.settle()
    if live { model.liveness.saw(activity: Date()) }
    return (StatusItemController(model: model, themes: ThemeStore(appearance: .dark)), model)
  }

  @Test("a reading is drawn once, and an unchanged reading is not drawn again")
  func drawsOnce() async throws {
    let (controller, _) = try await controller(live: false)
    let button = FakeButton()
    controller.refresh(on: button)
    #expect(button.draws == 1)
    controller.refresh(on: button)
    #expect(button.draws == 1)
  }

  /// The one piece of motion. It is worth checking that it happens when the
  /// session changes and at no other time, because a fade per frame is what
  /// the idle budget forbids.
  @Test("the session going quiet fades, and the first picture does not")
  func crossFades() async throws {
    let (controller, model) = try await controller(live: true)
    controller.reducesMotion = { false }
    let button = FakeButton()
    controller.refresh(on: button)
    #expect(button.fades == 0, "the first picture has nothing to fade from")

    model.liveness.clear()
    controller.refresh(on: button)
    #expect(button.draws == 2)
    #expect(button.fades == 1)

    // And nothing changing changes nothing.
    controller.refresh(on: button)
    #expect(button.fades == 1)
  }

  @Test("with less motion asked for, the picture changes without a fade")
  func reducedMotion() async throws {
    let (controller, model) = try await controller(live: true)
    controller.reducesMotion = { true }
    let button = FakeButton()
    controller.refresh(on: button)
    model.liveness.clear()
    controller.refresh(on: button)
    #expect(button.draws == 2)
    #expect(button.fades == 0)
  }

  @Test("a live session is the filled mark and its size")
  func liveSession() async throws {
    let (controller, model) = try await controller(live: true)
    let button = FakeButton()
    controller.refresh(on: button)
    let reading = try #require(StatusReading.make(from: model))
    #expect(reading.isLive)
    #expect(button.image?.isTemplate == true)
    #expect(button.number.hasSuffix(TokenFormat.brief(reading.totalTokens)))
    #expect(button.tooltip == "ctxscope, \(StatusVoice.value(reading))")
    #expect(button.value.hasSuffix("of \(TokenFormat.axis(reading.window))"))
  }

  @Test("an idle session has no number, and still says what it is")
  func idleSession() async throws {
    let (controller, _) = try await controller(live: false)
    let button = FakeButton()
    controller.refresh(on: button)
    #expect(button.image?.isTemplate == true)
    #expect(button.number.isEmpty)
    #expect(button.tooltip.hasSuffix(", idle"))
    #expect(button.value.hasSuffix(", idle"))
  }

  @Test("with nothing in focus it still has a name, a value and a tooltip")
  func nothingInFocus() async throws {
    let (controller, model) = try await controller(live: false)
    model.focus(session: nil)
    await model.settle()
    let button = FakeButton()
    controller.refresh(on: button)
    #expect(button.draws == 1)
    #expect(button.image?.isTemplate == true)
    #expect(button.number.isEmpty)
    #expect(button.tooltip == "ctxscope, no session in focus")
    #expect(button.value == "no session in focus")
  }
}
