internal import Foundation

public struct Theme: Sendable, Hashable, Codable, Identifiable {
  public let name: String
  public let appearance: Appearance
  public let surface: SurfaceRoles
  public let line: LineRoles
  public let text: TextRoles
  public let control: ControlRoles
  public let status: StatusRoles
  public let shadow: ShadowRoles
  public let kind: KindRoles
  public let chart: ChartRoles
  public let chrome: ChromeRoles

  public var id: String { name }

  public enum Appearance: String, Sendable, Hashable, Codable, CaseIterable {
    case dark
    case light
  }

  public var type: Typography { Typography.standard }

  public var metrics: Metrics { Metrics.standard }
}
