public import CoreGraphics

public struct Metrics: Sendable, Hashable {
  public static let standard = Metrics()

  public let hairline: CGFloat = 1

  public let window = Window()
  public let header = Header()
  public let control = Control()
  public let segmented = Segmented()
  public let pill = Pill()
  public let search = Search()
  public let card = Card()
  public let table = Table()
  public let swatch = Swatch()
  public let list = DefinitionList()
  public let code = Code()
  public let badge: CGFloat = 16
  public let popover = Popover()
  public let menuBar = MenuBar()
  public let timeline = Timeline()
  public let magnifier = Magnifier()

  public struct Window: Sendable, Hashable {
    public let size = CGSize(width: 1440, height: 900)
    public let cornerRadius: CGFloat = 10
    public let sidebarWidth: CGFloat = 340
    // Only a snapshot draws the traffic lights.
    public let trafficLight: CGFloat = 12
    public let trafficLightGap: CGFloat = 8
  }

  public struct Header: Sendable, Hashable {
    public let height: CGFloat = 52
    public let padding: CGFloat = 16
    public let gap: CGFloat = 16
    public let trafficLightReserve: CGFloat = 60
    public let pickerLeading: CGFloat = 24
  }

  public struct Control: Sendable, Hashable {
    public let height: CGFloat = 28
    public let tallHeight: CGFloat = 30
    public let cornerRadius: CGFloat = 6
    public let buttonPadding: CGFloat = 12
    public let popUpPadding: CGFloat = 10
    public let popUpGap: CGFloat = 8
    public let chevron: CGFloat = 10
    public let chevronStroke: CGFloat = 1.5
    public let stepperArrow: CGFloat = 12
    public let stepperArrowStroke: CGFloat = 1.6
    public let stepperGap: CGFloat = 4
    public let stepperLabelWidth: CGFloat = 120
    public let ellipsis: CGFloat = 12
    public let buttonGap: CGFloat = 8
    public let focusRingWidth: CGFloat = 3
  }

  public struct Segmented: Sendable, Hashable {
    public let trackPadding: CGFloat = 2
    public let trackRadius: CGFloat = 7
    public let thumbRadius: CGFloat = 5
    public let toolbarHeight: CGFloat = 24
    public let toolbarPadding: CGFloat = 14
    public let filterHeight: CGFloat = 22
    public let filterPadding: CGFloat = 12
  }

  public struct Pill: Sendable, Hashable {
    public let height: CGFloat = 24
    public let padding: CGFloat = 10
    public let gap: CGFloat = 6
    public let dot: CGFloat = 7
    public let statusDot: CGFloat = 6
    public let statusGap: CGFloat = 5
  }

  public struct Search: Sendable, Hashable {
    public let width: CGFloat = 180
    public let height: CGFloat = 26
    public let glass: CGFloat = 12
    public let glassStroke: CGFloat = 1.5
    public let glassInset: CGFloat = 8
    public let textInset: CGFloat = 26
    public let trailingInset: CGFloat = 8
  }

  public struct Card: Sendable, Hashable {
    public let statPadding = Insets(vertical: 14, horizontal: 16)
    public let statRadius: CGFloat = 10
    public let statGap: CGFloat = 4
    public let infoPadding = Insets(vertical: 12, horizontal: 14)
    public let infoRadius: CGFloat = 8
    public let infoGap: CGFloat = 5
    public let infoHeaderGap: CGFloat = 8
    public let gap: CGFloat = 12
  }

  public struct Table: Sendable, Hashable {
    public let headerHeight: CGFloat = 28
    public let rowHeight: CGFloat = 30
    public let compactHeaderHeight: CGFloat = 26
    public let compactRowHeight: CGFloat = 28
    public let cellPadding: CGFloat = 10
    public let columnGap: CGFloat = 12
    public let blocks = BlockColumns()
    public let prompts = PromptColumns()
  }

  public struct BlockColumns: Sendable, Hashable {
    public let kind: CGFloat = 104
    public let size: CGFloat = 80
    public let carried: CGFloat = 84
    public let used: CGFloat = 72
    public let cost: CGFloat = 96
  }

  public struct PromptColumns: Sendable, Hashable {
    public let number: CGFloat = 28
    public let requests: CGFloat = 90
    public let added: CGFloat = 110
    public let cost: CGFloat = 80
    public let breaks: CGFloat = 96
  }

  public struct Swatch: Sendable, Hashable {
    public let table: CGFloat = 8
    public let legend: CGFloat = 10
    public let compact: CGFloat = 7
    public let cornerRadius: CGFloat = 2
    public let tableGap: CGFloat = 7
    public let legendGap: CGFloat = 6
    public let compactGap: CGFloat = 5
  }

  public struct DefinitionList: Sendable, Hashable {
    public let popoverRowGap: CGFloat = 9
    public let columnGap: CGFloat = 12
  }

  public struct Code: Sendable, Hashable {
    public let padding: CGFloat = 12
    public let cornerRadius: CGFloat = 8
    public let maxHeight: CGFloat = 250
    public let inlinePadding = Insets(vertical: 7, horizontal: 10)
  }

  public struct Timeline: Sendable, Hashable {
    public let padding = Insets(vertical: 22, horizontal: 28)
    public let sectionGap: CGFloat = 22
    public let chartGap: CGFloat = 10
    public let sidebarPadding: CGFloat = 22
    public let sidebarGap: CGFloat = 22
    public let detailGap: CGFloat = 10
    public let headingGap: CGFloat = 8
    public let axisWidth: CGFloat = 36
    public let axisGap: CGFloat = 8
    public let costLabelInset: CGFloat = 2
    public let bandHeight: CGFloat = 26
    public let bandRadius: CGFloat = 4
    public let bandLabelInset: CGFloat = 2
    public let bandChipInset: CGFloat = 6
    public let badgeInset: CGFloat = 5
    public let badgeGap: CGFloat = 2
    public let plotHeight: CGFloat = 280
    public let costHeight: CGFloat = 56
    public let costRadius: CGFloat = 1
    public let costMinimum: CGFloat = 2
    public let columnGap: CGFloat = 2
    public let columnGapShare: CGFloat = 0.18
    public let blockGap: CGFloat = 0.5
    // In 2x device pixels: rules beside shorter blocks line up across columns as stripes.
    public let blockGapMinimumPixels: CGFloat = 12

    public func separates(below: CGFloat, above: CGFloat) -> Bool {
      min(below, above) >= blockGapMinimumPixels
    }
    public let markerWidth: CGFloat = 1.5
    public let markerDash: CGFloat = 3
    public let markerDashGap: CGFloat = 1.5
    public let markerOverhang: CGFloat = 4
    public let badgeRise: CGFloat = 12
    public let legendMarkerHeight: CGFloat = 12
    // Set to the heights in `Typography.lines`, not SwiftUI's, which are a point taller.
    public let headingHeight: CGFloat = 15
    public let legendHeight: CGFloat = 15.5
    public let axisLineHeight: CGFloat = 11.5
  }

  public struct Magnifier: Sendable, Hashable {
    public let width: CGFloat = 340
    public let padding = Insets(vertical: 10, horizontal: 12)
    public let cornerRadius: CGFloat = 10
    public let columnWidth: CGFloat = 30
    public let columnHeight: CGFloat = 352
    public let columnRadius: CGFloat = 3
    public let gap: CGFloat = 10
    public let rowGap: CGFloat = 8
    public let rows = 22
    public let rowHeight: CGFloat = 16
    public let rowPadding: CGFloat = 6
    public let rowRadius: CGFloat = 4
    public let titleGap: CGFloat = 2
    public let subtitleGap: CGFloat = 8
    public let offset: CGFloat = 16
  }

  public struct Insets: Sendable, Hashable {
    public let vertical: CGFloat
    public let horizontal: CGFloat
  }

  public struct Edges: Sendable, Hashable {
    public let top: CGFloat
    public let horizontal: CGFloat
    public let bottom: CGFloat
  }
}
