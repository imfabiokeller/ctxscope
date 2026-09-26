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
    // Connect edits the harness's settings and listens for its hook events.
    // It owns no domain types, so it depends on nothing.
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
    // The status item, its image, the launch decisions and the shortcut live
    // in the app target, so what can be tested about them is tested here.
    .testTarget(name: "ctxscopeTests", dependencies: ["ctxscope"], swiftSettings: strict),
    // The demo generator lives in the CLI, and what it writes is checked by
    // reading it back through the adapter.
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
    // A warning is something nobody has decided about yet. The gate decides.
    .treatAllWarnings(as: .error),
  ]
}
