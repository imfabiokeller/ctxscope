internal import Foundation

/// Every color the instrument shows. A theme is data: a JSON file in the
/// bundle, and nothing in a view is allowed to name a color of its own.
///
/// Colors are grouped by what they are for: surfaces, lines, text, controls,
/// status, the six kinds, the charts and the chrome a snapshot draws.
public struct Theme: Sendable, Hashable, Codable, Identifiable {
  public let name: String
  /// Which system appearance this theme belongs to.
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

  /// Typography, which is one source of truth for the same reason colors are.
  public var type: Typography { Typography.standard }

  /// Sizes, spacing and radii. Not part of the file, because they do not
  /// change with the appearance.
  public var metrics: Metrics { Metrics.standard }
}
