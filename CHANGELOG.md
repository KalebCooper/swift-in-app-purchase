# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## Unreleased

- `InAppPurchaseUI` replaces `TipJarView` and `TipJarCopy` with a bridge to SwiftUI. `PurchaseStore.purchase(_:using:options:)` purchases through the view's `@Environment(\.purchase)`, which is the purchase path on visionOS, and `refreshingPurchases(_:)` refreshes the store whenever the scene becomes active. For a ready-made storefront, use StoreKit's `StoreView`.
- `PurchaseStore(productIDs:)` now sells through the App Store. Only transactions that pass StoreKit's verification are delivered or counted; a purchase that fails verification throws `unverified`. Every `StoreKitError` and `Product.PurchaseError` maps to a `PurchaseError.Code` with the StoreKit error kept as `underlying`, and an error StoreKit adds later maps to `unknown`. A second store listening for transactions in the same process logs a fault.
- `PurchaseStore` is implemented. `start()` and `start(handling:)` start the transaction listener, retry unfinished transactions, compute entitlements, and load products; the handler receives every transaction once, one at a time, and the store finishes it only after the handler returns. `purchasedProductIDs`, `isEntitled(to:)`, `product(id:)`, `missingProductIDs`, `loadError`, `isLoadingProducts`, `refresh()`, `restore()`, and `preview(products:purchasedProductIDs:)` are added; `entitlements`, `finish(_:)`, `listenForTransactionUpdates(_:)`, and `loadProducts(_:)` are removed, and `products` is an array in the order the identifiers were given. `purchase(_:options:)` returns only after delivery and throws `deliveryFailed` when the handler threw or no handler can deliver a consumable; it is unavailable on visionOS.
- `MockPurchaseClient` is now `Sendable` rather than main-actor isolated, and `init()` takes no arguments. Set `entitlements`, `products`, `productsError`, `purchaseResult`, `syncResult`, and `unfinishedTransactions` instead of `failure` and `outcome`. `finishedTransactions` replaces `finished`, `nextFinishedTransaction()` waits for the next finish, and `send(_:)` delivers a transaction update.
- `PurchaseStore.init(client:)` is replaced by `PurchaseStore.init(productIDs:)`, which sells through the App Store, and, in `InAppPurchaseTesting`, `PurchaseStore.init(client:productIDs:)`, which takes a `MockPurchaseClient`.
- `PurchaseClient` and `StoreKitPurchaseClient` are no longer public. A test or preview uses `MockPurchaseClient`.
- Added `PurchaseError` with an open `Code` and an `underlying` error. `PurchaseError.Code` gains `deliveryFailed`, `invalidPresentationContext`, `networkUnavailable`, `notAvailableInStorefront`, `notEntitled`, `paymentMethodBindingRequired`, `unknown`, `unsupported`, `unverified`, and `userCancelled`. `failedVerification` is now `unverified`, `system` is now `systemError`, and `PurchaseError` no longer carries a `productID`.
- Added `TransactionEvent`, which reports a purchase and a revocation as separate cases.
- Added `Entitlement`, a set of product identifiers that each unlock the same feature.
- `PurchaseOutcome` cases are now `pending`, `success`, and `userCancelled`, and the enum is no longer `Hashable`.
- `PurchaseTransaction` gains `appAccountToken`, `isUpgraded`, and `originalID`, and `purchaseDate` now defaults to the current date. `PurchaseProduct.price` now defaults to zero.
- Removed `VerificationPolicy`. Unverified transactions are never delivered or counted.
