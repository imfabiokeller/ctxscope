// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "ctxscope",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "ScopeCore", targets: ["ScopeCore"]),
    .library(name: "ScopeCapture", targets: ["ScopeCapture"]),
    .library(name: "ScopeConnect", targets: ["ScopeConnect"]),
    .library(name: "ScopeUI", targets: ["ScopeUI"]),
    .executable(name: "ctxscope-cli", targets: ["ctxscope-cli"]),
    .executable(name: "ctxscope-snapshots", targets: ["ctxscope-snapshots"]),
    .executable(name: "ctxscope", targets: ["ctxscope"]),
  ],
  targets: [
    .target(name: "ScopeCore", swiftSettings: strict),
    .target(name: "ScopeCapture", dependencies: ["ScopeCore"], swiftSettings: strict),
    .target(name: "ScopeConnect", swiftSettings: strict),
    .target(
      name: "ScopeUI",
      dependencies: ["ScopeCore", "ScopeCapture", "ScopeConnect"],
      resources: [.copy("Resources/Themes")],
      swiftSettings: strict
    ),
    .executableTarget(
      name: "ctxscope",
      dependencies: ["ScopeCore", "ScopeUI", "ScopeConnect"],
      swiftSettings: strict
    ),
    .executableTarget(
      name: "ctxscope-snapshots",
      dependencies: ["ScopeCore", "ScopeUI", "ScopeConnect"],
      swiftSettings: strict
    ),
    .executableTarget(
      name: "ctxscope-cli",
      dependencies: ["ScopeCore", "ScopeCapture", "ScopeConnect"],
      swiftSettings: strict
    ),
    .testTarget(name: "ScopeCoreTests", dependencies: ["ScopeCore"], swiftSettings: strict),
    .testTarget(name: "ScopeConnectTests", dependencies: ["ScopeConnect"], swiftSettings: strict),
    .testTarget(
      name: "ScopeCaptureTests",
      dependencies: ["ScopeCapture"],
      resources: [.copy("Fixtures")],
      swiftSettings: strict
    ),
    .testTarget(name: "ScopeUITests", dependencies: ["ScopeUI"], swiftSettings: strict),
    .testTarget(name: "ctxscopeTests", dependencies: ["ctxscope"], swiftSettings: strict),
    .testTarget(
      name: "ctxscope-cliTests",
      dependencies: ["ctxscope-cli", "ScopeCapture", "ScopeCore"],
      swiftSettings: strict
    ),
  ]
)

var strict: [SwiftSetting] {
  [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .treatAllWarnings(as: .error),
  ]
}
