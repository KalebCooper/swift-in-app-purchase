// swift-tools-version: 6.4

import PackageDescription

// Three products, one dependency direction. InAppPurchase is the StoreKit 2 client, its observable
// state, and its value types, with no UI framework behind it. InAppPurchaseUI is the SwiftUI bridge
// and InAppPurchaseTesting is the mock client; both depend on the core and nothing depends on them.
let package = Package(
  name: "swift-in-app-purchase",
  platforms: [
    .iOS(.v27), .macOS(.v27), .tvOS(.v27), .visionOS(.v27), .watchOS(.v27),
  ],
  products: [
    .library(name: "InAppPurchase", targets: ["InAppPurchase"]),
    .library(name: "InAppPurchaseTesting", targets: ["InAppPurchaseTesting"]),
    .library(name: "InAppPurchaseUI", targets: ["InAppPurchaseUI"]),
  ],
  targets: [
    .target(name: "InAppPurchase", swiftSettings: swiftSettings),
    .target(
      name: "InAppPurchaseTesting",
      dependencies: ["InAppPurchase"],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "InAppPurchaseUI",
      dependencies: ["InAppPurchase"],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "InAppPurchaseTests",
      dependencies: ["InAppPurchase", "InAppPurchaseTesting"],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)

// Library code is nonisolated by default (the inverse of an app target's MainActor default), so every
// `@MainActor` in the package is written where it applies; async entry points run on the caller's
// actor until they truly suspend; and every `unsafe` is spelled out.
var swiftSettings: [SwiftSetting] {
  [
    .defaultIsolation(nil),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .strictMemorySafety(),
  ]
}
