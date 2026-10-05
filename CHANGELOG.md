# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## Unreleased

- `MockPurchaseClient` is now `Sendable` rather than main-actor isolated, and `init()` takes no arguments. Set `entitlements`, `products`, `productsError`, `purchaseResult`, `syncResult`, and `unfinishedTransactions` instead of `failure` and `outcome`. `finishedTransactions` replaces `finished`, `nextFinishedTransaction()` waits for the next finish, and `send(_:)` delivers a transaction update.
- `PurchaseStore.init(client:)` is replaced by `PurchaseStore.init(productIDs:)`, which sells through the App Store, and, in `InAppPurchaseTesting`, `PurchaseStore.init(client:productIDs:)`, which takes a `MockPurchaseClient`.
- `PurchaseClient` and `StoreKitPurchaseClient` are no longer public. A test or preview uses `MockPurchaseClient`.
- Added `PurchaseError` with an open `Code` and an `underlying` error. `PurchaseError.Code` gains `deliveryFailed`, `invalidPresentationContext`, `networkUnavailable`, `notAvailableInStorefront`, `notEntitled`, `paymentMethodBindingRequired`, `unknown`, `unsupported`, `unverified`, and `userCancelled`. `failedVerification` is now `unverified`, `system` is now `systemError`, and `PurchaseError` no longer carries a `productID`.
- Added `TransactionEvent`, which reports a purchase and a revocation as separate cases.
- Added `Entitlement`, a set of product identifiers that each unlock the same feature.
- `PurchaseOutcome` cases are now `pending`, `success`, and `userCancelled`, and the enum is no longer `Hashable`.
- `PurchaseTransaction` gains `appAccountToken`, `isUpgraded`, and `originalID`, and `purchaseDate` now defaults to the current date. `PurchaseProduct.price` now defaults to zero.
- Removed `VerificationPolicy`. Unverified transactions are never delivered or counted.
