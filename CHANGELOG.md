# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## Unreleased

## 0.2.0 - 2026-10-20

- Changed `refreshingPurchases(_:)` to refresh when the scene returns from the background instead of each time it becomes active, so a system alert or StoreKit's own purchase confirmation no longer triggers a refresh in the middle of a purchase. On macOS, where a window stays active while another app has focus, it still refreshes when the scene becomes active.
- Added a section on refreshing when the app returns to the foreground from UIKit or AppKit to Using the Store Outside SwiftUI.
- Changed the log subsystem from `InAppPurchase` to `dev.cooperlabs.InAppPurchase`, and added info-level lines for every entitlement read, with the transactions it returned and whether it was applied or superseded; every transaction update received; every unfinished transaction collected; every finish; and how StoreKit ended each purchase. Lines carry transaction and product identifiers only.
- Changed `PurchaseStore`'s purchase methods to deliver unfinished transactions and recompute entitlements before returning, after a purchase StoreKit reported as cancelled or failed. StoreKit can record such a purchase, as it can when the app leaves the foreground while its confirmation is on screen, and it now reaches the handler without waiting for the next refresh or launch. The outcome is still what StoreKit reported.

## 0.1.0 - 2026-10-20

- Added `PurchaseStore`, an `@Observable` store that sells through the App Store with `PurchaseStore(productIDs:)`. `start()` and `start(handling:)` start the transaction listener, compute entitlements, retry unfinished transactions, and load products. The handler receives every transaction at least once, one at a time, and the store finishes it only after the handler returns. With no handler, `start()` finishes non-consumables and auto-renewable subscriptions and leaves consumables and non-renewing subscriptions unfinished until `start(handling:)` supplies one. The handler must not call back into the store: a refresh from inside it returns without waiting for deliveries, and a purchase throws `unsupported`.
- Added strict verification. Only transactions that pass StoreKit's verification are delivered, counted, or finished, and a purchase that fails verification throws `unverified`. A second store listening for transactions in the same process logs a fault.
- Added `purchasedProductIDs`, `isEntitled(to:)`, `product(id:)`, `products`, `missingProductIDs`, `loadError`, `isLoadingProducts`, `refresh()`, and `restore()`. A subscription counts as owned for as long as the App Store reports it current, which includes a billing grace period. A consumable is never counted in `purchasedProductIDs`.
- Added `PurchaseStore.purchase(_:options:)`, which returns only after delivery and throws `deliveryFailed` when the handler threw or no handler can deliver a consumable. It is unavailable on visionOS, where a purchase needs its scene.
- Added `Purchaser` and `PurchaseStore.purchase(_:using:options:)`, which purchase in a presentation context the app supplies. A `Purchaser` that throws a `PurchaseError` has that error passed through unchanged, so its code is kept.
- Added, in `InAppPurchaseUI`, `purchase(_:confirmIn:options:)` for a `UIScene`, a `UIViewController`, or an `NSWindow`, so a purchase can be confirmed from UIKit, AppKit, or a service with no view of its own. On visionOS, a purchase can be confirmed in a scene as well as through `@Environment(\.purchase)`.
- Added `PurchaseStore.loadProducts()`, which loads products or joins the load in progress, returns them, and throws on failure while keeping the products already loaded. `refresh()` also reloads when a requested product is missing.
- Added `PurchaseStore.pendingProductIDs`, the products whose purchase awaits approval, such as an Ask to Buy request.
- Added, in `InAppPurchaseUI`, `purchase(_:using:options:)` through the view's `@Environment(\.purchase)` and `refreshingPurchases(_:)`, which refreshes the store whenever the scene becomes active.
- Added `PurchaseError` with an open `Code` and an `underlying` error. Every `StoreKitError` and `Product.PurchaseError` maps to a code with the StoreKit error kept as `underlying`, and an error StoreKit adds later maps to `unknown`. Codes include `deliveryFailed`, `invalidPresentationContext`, `networkUnavailable`, `notAvailableInStorefront`, `notEntitled`, `paymentMethodBindingRequired`, `systemError`, `unknown`, `unsupported`, `unverified`, and `userCancelled`.
- Added `Entitlement`, a set of product identifiers that each unlock the same feature, `TransactionEvent`, which reports a purchase and a revocation as separate cases, and `PurchaseOutcome`, with the cases `pending`, `success`, and `userCancelled`.
- Added `PurchaseProduct` and `PurchaseTransaction`, which carry their StoreKit originals as an escape hatch. `PurchaseTransaction` includes `appAccountToken`, `isUpgraded`, and `originalID`.
- Added `MockPurchaseClient` in `InAppPurchaseTesting`, with `PurchaseStore.init(client:productIDs:)` to drive a store without the App Store. It keeps entitlements as StoreKit does: a purchased or sent non-consumable or auto-renewable subscription joins `entitlements`, a sent revocation leaves them, and every purchased or sent transaction stays in `unfinishedTransactions` until finished. `purchaseResults` sets an outcome per product, `purchaseRequests` records every purchase, `finishedTransactions` lists what the store finished, `nextFinishedTransaction()` waits for the next finish, and `send(_:)` delivers a transaction update.
- Added `PurchaseStore.preview(products:purchasedProductIDs:)` for rendering locked and unlocked states in a SwiftUI preview.
- Added documentation articles: Getting Started, Delivering Transactions, Gating Features, Handling Errors, and Using the Store Outside SwiftUI in `InAppPurchase`, Building a Paywall in `InAppPurchaseUI`, and Testing Purchases in `InAppPurchaseTesting`.
- Added an example app, `Examples/PurchaseExample`. It sells tips, Pro as a one-time purchase or a subscription, and consumable coins through one `PurchaseStore` and one transaction handler, runs in the simulator against a bundled StoreKit configuration with no signing, and tests its coin delivery with `MockPurchaseClient`.
- Set the minimum platforms to iOS, Mac Catalyst, macOS, tvOS, visionOS, and watchOS 26.
