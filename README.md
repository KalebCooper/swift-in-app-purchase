# swift-in-app-purchase

[![CI](https://github.com/KalebCooper/swift-in-app-purchase/actions/workflows/ci.yml/badge.svg)](https://github.com/KalebCooper/swift-in-app-purchase/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

In-app purchases for Swift apps, built on StoreKit 2.

`PurchaseStore` is the observable state a view renders: the products on offer and what the customer
owns. It reads from the App Store in an app and from `MockPurchaseClient` in a test or preview. The
SwiftUI purchase and foreground-refresh bridge ships in a separate product.

> **Status:** pre-release. `PurchaseStore` and the App Store client are implemented, the store is
> tested against the mock client, and no version has been tagged.

## Installation

| Product | Add it to |
|---|---|
| `InAppPurchase` | Any target that loads products, purchases, or reads entitlements. No UI framework behind it. |
| `InAppPurchaseUI` | A SwiftUI target that purchases through `@Environment(\.purchase)` or refreshes on foreground. Depends on `InAppPurchase`. |
| `InAppPurchaseTesting` | A test or preview target. Depends on `InAppPurchase`. |

Versions follow semantic versioning, and every change is recorded in [CHANGELOG.md](CHANGELOG.md).

## Requirements

- Swift 6.4 tools, Swift 6 language mode
- iOS 27 / macOS 27 / tvOS 27 / visionOS 27 / watchOS 27
- No dependencies

## License

MIT. See [LICENSE](LICENSE).
