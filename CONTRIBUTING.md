# Contributing to swift-in-app-purchase

Thanks for your interest. The public surface follows semantic versioning: a breaking change lands in
a major release, never a minor one.

## Getting started

1. Fork and clone the repository.
2. Open the package directory in Xcode 27 or later.
3. Build and run tests on the `swift-in-app-purchase-Package` scheme (⌘U), or run the package tests
   from the command line on macOS.

`Examples/PurchaseExample` is a runnable iOS app that uses the package end to end. Open its project
in Xcode and run it in the simulator; it is the reference for how the pieces fit together.

## Guidelines

- **Public API:** every public symbol needs a DocC comment.
- **Concurrency:** library code is nonisolated by default, so every `@MainActor` is written where it
  applies. State is `@Observable`. No Combine, no `ObservableObject`, no `DispatchQueue`.
- **Layering:** `InAppPurchase` has no UI framework behind it. SwiftUI belongs in `InAppPurchaseUI`
  and test doubles in `InAppPurchaseTesting`; both depend on the core, never the reverse.
- **Tests:** Swift Testing only, run against `MockPurchaseClient`. No test reaches the App Store.
- **Style:** `swift format lint --strict --recursive Package.swift Sources Tests Examples` must report zero
  findings. Parameters, stored properties, and enum cases are alphabetical within their grouping
  unless initialization order or a logical dependency dictates otherwise.
- **Scope:** the package wraps StoreKit 2 on the device. The App Store Server API is out of scope.
  Open an issue to discuss additions before investing in a large PR.

## Pull requests

- Target `main`. One concern per PR.
- Update `CHANGELOG.md` under **Unreleased**.
- CI must pass.

## Reporting issues

Use the issue templates and include a minimal reproduction where possible.
