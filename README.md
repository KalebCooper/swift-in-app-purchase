# swift-in-app-purchase

[![CI](https://github.com/KalebCooper/swift-in-app-purchase/actions/workflows/ci.yml/badge.svg)](https://github.com/KalebCooper/swift-in-app-purchase/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

In-app purchases for Swift apps, built on StoreKit 2: one observable store that delivers every
transaction and keeps entitlements current.

> **Status:** 0.1.0. The store, the App Store client, the SwiftUI bridge, and the mock client are
> implemented, and the store is tested against the mock client.

## Features

- **Strict verification.** A transaction that fails StoreKit's verification is never delivered,
  counted, or finished.
- **Deliver, then finish.** Every transaction reaches one handler, at least once and one at a time,
  and the store finishes it only after the handler returns, so a consumable is never lost.
- **Entitlements that stay current.** `isEntitled(to:)` follows renewals, expiry, and refunds on its
  own, and a subscriber in a billing grace period stays entitled.
- **Purchase where the customer is looking.** Confirm a purchase in a SwiftUI view's
  `@Environment(\.purchase)`, a `UIScene`, a `UIViewController`, or an `NSWindow`, and refresh the
  store whenever the app returns to the foreground.
- **Mock client and previews.** `MockPurchaseClient` drives the store in tests without the App
  Store, and `PurchaseStore.preview` renders locked and unlocked states in a SwiftUI preview.

## Quick start

Add the package:

```swift
dependencies: [
  .package(url: "https://github.com/KalebCooper/swift-in-app-purchase.git", from: "0.1.0")
]
```

Versions follow semantic versioning, and every change is recorded in [CHANGELOG.md](CHANGELOG.md). A
0.x minor release may break the API, and the changelog says how to adapt.

Create one store with the identifier of every product you sell:

```swift
@State private var store = PurchaseStore(productIDs: [
  "coins.100", "coins.500", "pro.lifetime", "pro.monthly", "pro.yearly", "tip.large",
  "tip.medium", "tip.small",
])
```
Source: [Examples/PurchaseExample/PurchaseExample/PurchaseExampleApp.swift](Examples/PurchaseExample/PurchaseExample/PurchaseExampleApp.swift)

Put it in the environment and start it once, from the app's root, with a handler that delivers what
the customer paid for:

```swift
ContentView(thankedTransactionIDs: thankedTransactionIDs)
  .environment(store)
  .refreshingPurchases(store)
  .task {
    // One handler delivers every product, one transaction at a time. The store finishes
    // each transaction only after the handler returns.
    await store.start { event in
      switch event {
      case .purchased(let transaction) where transaction.productID.hasPrefix("tip."):
        // A transaction can arrive more than once, so key the thank-you on its id.
        thankedTransactionIDs.insert(transaction.id)
      case .purchased(let transaction) where transaction.productID.hasPrefix("coins."),
        .revoked(let transaction) where transaction.productID.hasPrefix("coins."):
        try CoinDelivery.deliver(event, in: container.mainContext)
      default:
        // Owning Pro is the content, so there is nothing to deliver.
        break
      }
    }
  }
```
Source: [Examples/PurchaseExample/PurchaseExample/PurchaseExampleApp.swift](Examples/PurchaseExample/PurchaseExample/PurchaseExampleApp.swift)

Starting computes what the customer owns before it loads products, so a gated view is right even
offline. `refreshingPurchases(_:)` refreshes the store each time the app returns to the foreground.

Declare what each feature needs, then gate on it with `store.isEntitled(to: .pro)`:

```swift
extension Entitlement {
  /// Pro is unlocked by the one-time purchase or by either subscription.
  static let pro = Entitlement(["pro.lifetime", "pro.monthly", "pro.yearly"])
}
```
Source: [Examples/PurchaseExample/PurchaseExample/Pro/Entitlement+Pro.swift](Examples/PurchaseExample/PurchaseExample/Pro/Entitlement+Pro.swift)

## Common tasks

### Gate a feature

Ask the store whether the customer owns any product in the entitlement. The store is observable, so
the view updates when a purchase, renewal, expiry, or refund changes the answer.

```swift
if store.isEntitled(to: .pro) {
  Section {
    Label("Pro is unlocked", systemImage: "checkmark.seal.fill")
  } footer: {
    Text("A subscriber in a billing grace period stays unlocked.")
  }
} else {
  Section("Unlock Pro") {
    Button("See Subscriptions") { isShowingSubscriptions = true }
    if let lifetime = store.product(id: "pro.lifetime") {
      PaywallButton(product: lifetime)
    }
  }
}
```
Source: [Examples/PurchaseExample/PurchaseExample/Pro/ProGate.swift](Examples/PurchaseExample/PurchaseExample/Pro/ProGate.swift)

A subscription bundle's own identifier never appears in `purchasedProductIDs`, so gate on the
bundled subscriptions:

```swift
extension Entitlement {
  // "bundle.monthly" bundles these two. Its own ID is never in purchasedProductIDs.
  static let musicAndVideo = Entitlement(["music.monthly", "video.monthly"])
}
```

### Sell with StoreKit views

`StoreView`, `ProductView`, and `SubscriptionStoreView` need no extra code. Their purchases arrive as
transaction updates, which the store delivers to your handler. To close a paywall sheet after a
purchase, dismiss it when `isEntitled(to:)` changes.

```swift
// A purchase made in StoreView arrives as a transaction update, which the store delivers to
// the app's handler. Attaching .onInAppPurchaseCompletion would take it off that path.
StoreView(ids: ["tip.small", "tip.medium", "tip.large"])
```
Source: [Examples/PurchaseExample/PurchaseExample/Tips/TipJarScreen.swift](Examples/PurchaseExample/PurchaseExample/Tips/TipJarScreen.swift)

### Build a custom purchase button

Purchase a product from `store.products` through the view's `@Environment(\.purchase)`. The call
returns `.success` only after your handler has delivered the transaction and the store has finished
it, so the entitlement is already current.

```swift
private func buy() async {
  isPurchasing = true
  defer { isPurchasing = false }
  do {
    // The view's purchase action shows the confirmation sheet in this scene.
    switch try await store.purchase(product, using: purchase) {
    case .success:
      // The handler has delivered the content and the store has finished the transaction.
      status = nil
    case .pending:
      status = "Waiting for approval. The purchase arrives when it is approved."
    case .userCancelled:
      status = nil
    }
  } catch {
    status =
      switch error.code {
      case .deliveryFailed:
        "Paid, but delivery failed. It is retried the next time the app opens."
      case .userCancelled:
        nil
      default:
        "Purchase failed: \(error.code.rawValue)"
      }
  }
}
```
Source: [Examples/PurchaseExample/PurchaseExample/Pro/PaywallButton.swift](Examples/PurchaseExample/PurchaseExample/Pro/PaywallButton.swift)

A `.pending` purchase, such as an Ask to Buy request, puts its product in `store.pendingProductIDs`
until its transaction arrives or the customer owns it, so a view can show the request as waiting
rather than offering the purchase again. The set lives in memory only: a relaunch forgets it, a
decline sends nothing, and purchases started in StoreKit's views are not tracked.

Cancelling the sheet returns `.userCancelled` rather than throwing; the error arm is a safeguard.
StoreKit can record a purchase and still report it cancelled or failed, as it can when the app
leaves the foreground while StoreKit's own confirmation is on screen. The store then finds the
transaction among the unfinished ones, delivers it, and returns `.success`. Only a transaction
dated at or after the call began counts, so an earlier purchase of the same product never does.

### Deliver consumables

Grant the content in the handler, keyed on `transaction.id` so a redelivery changes nothing, and save
before returning.

```swift
/// Records the coins `event` grants, or removes them when it is a revocation. Saves before
/// returning, because the store finishes the transaction as soon as the handler returns.
static func deliver(_ event: TransactionEvent, in context: ModelContext) throws {
  switch event {
  case .purchased(let transaction):
    // A transaction can arrive more than once, so grant its coins only the first time.
    guard try grants(for: transaction, in: context).isEmpty else { return }
    let coins = coinsPerPack[transaction.productID, default: 0] * transaction.quantity
    context.insert(CoinGrant(coins: coins, transactionID: transaction.id))
  case .revoked(let transaction):
    // A revocation carries the id of the purchase it revokes.
    for grant in try grants(for: transaction, in: context) {
      context.delete(grant)
    }
  }
  try context.save()
}
```
Source: [Examples/PurchaseExample/PurchaseExample/Coins/CoinDelivery.swift](Examples/PurchaseExample/PurchaseExample/Coins/CoinDelivery.swift)

If the handler throws, the store leaves the transaction unfinished and delivers it again on the next
`refresh()` or launch, and `purchase` throws `deliveryFailed`. Log the handler's error yourself; the
`PurchaseError` does not carry it.

### Handle refunds

A refund arrives as `.revoked`, with the same `id` as the purchase it takes back. Remove what that
purchase granted.

```swift
case .revoked(let transaction):
  // A revocation carries the id of the purchase it revokes.
  for grant in try grants(for: transaction, in: context) {
    context.delete(grant)
  }
```
Source: [Examples/PurchaseExample/PurchaseExample/Coins/CoinDelivery.swift](Examples/PurchaseExample/PurchaseExample/Coins/CoinDelivery.swift)

A refunded non-consumable or subscription simply leaves `purchasedProductIDs`; there is nothing to
undo.

### Retry a failed product load

`start()` loads products after it computes entitlements, and `refresh()` loads again when the last
load failed or a requested product was missing. To retry from a button, or to load before purchasing
a product that is not loaded yet, call `loadProducts()`. It returns the products and throws the
failure; a call while a load runs joins it rather than starting another.

```swift
Button("Retry") {
  Task { try? await store.loadProducts() }
}
.disabled(store.isLoadingProducts)
```

### Restore purchases

Entitlements stay in sync on their own, so restoring is rarely needed. `restore()` can ask the
customer to sign in, so call it only from a button.

```swift
private func restore() async {
  isRestoring = true
  defer { isRestoring = false }
  do {
    // Restoring can ask the customer to sign in, so it runs only from this button.
    try await store.restore()
    restoreError = nil
  } catch {
    restoreError = error
  }
}
```
Source: [Examples/PurchaseExample/PurchaseExample/Pro/ProGate.swift](Examples/PurchaseExample/PurchaseExample/Pro/ProGate.swift)

### Use the store from a service

The store needs no SwiftUI. Own one in whatever holds the app's long-lived services, and observe it
from a view model or service with `Observations`, which yields the current value first, then each
change, and ends when the iterating task is cancelled.

```swift
let changes = Observations { store.purchasedProductIDs }
for await purchased in changes {
  isPro = purchased.contains("pro.lifetime")
}
```

From UIKit or AppKit, purchase with `purchase(_:confirmIn:options:)` from `InAppPurchaseUI`. See
[Using the Store Outside SwiftUI](Sources/InAppPurchase/InAppPurchase.docc/UsingTheStoreOutsideSwiftUI.md)
for purchasing without a view, loading a product before buying it, and testing an adapter.

### Test with the mock

`MockPurchaseClient`, from `InAppPurchaseTesting`, answers the store from values the test sets. This
test runs the app's own delivery code against an in-memory store.

```swift
@Test func deliversCoinsOnce() async throws {
  let container = try ModelContainer(
    for: CoinGrant.self,
    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
  )
  let mock = MockPurchaseClient()
  mock.unfinishedTransactions = [
    PurchaseTransaction(id: 1, productID: "coins.100", productType: .consumable)
  ]
  let store = PurchaseStore(client: mock, productIDs: ["coins.100"])

  await store.start { event in
    try CoinDelivery.deliver(event, in: container.mainContext)
  }

  #expect(try balance(in: container) == 100)
  #expect(mock.finishedTransactions.map(\.id) == [1])
}
```
Source: [Examples/PurchaseExample/PurchaseExampleTests/CoinDeliveryTests.swift](Examples/PurchaseExample/PurchaseExampleTests/CoinDeliveryTests.swift)

- `entitlements`, `products`, `productsError`, `purchaseResult`, `purchaseResults` (per product),
  `syncResult`, and `unfinishedTransactions` set what the mock answers.
- `send(_:)` delivers a transaction update to a started store.
- The mock keeps entitlements as StoreKit does. A purchased or sent non-consumable or auto-renewable
  subscription joins `entitlements`, replacing the one for its product, a sent revocation leaves
  them, and every purchased or sent transaction stays in `unfinishedTransactions` until finished.
- `finishedTransactions` lists what the store finished, and `nextFinishedTransaction()` waits for the
  next one, so a test never sleeps. `purchaseRequests` records every purchase the store asked for.

### Preview

`PurchaseStore.preview(products:purchasedProductIDs:)` needs neither the mock nor the App Store. Pass
owned identifiers to preview the unlocked state. A preview store completes no purchase.

```swift
#Preview("Locked") {
  ProGate()
    .environment(
      PurchaseStore.preview(products: [
        PurchaseProduct(
          displayName: "Pro Lifetime",
          displayPrice: "$29.99",
          id: "pro.lifetime",
          type: .nonConsumable
        )
      ])
    )
}

#Preview("Unlocked") {
  ProGate()
    .environment(PurchaseStore.preview(purchasedProductIDs: ["pro.yearly"]))
}
```
Source: [Examples/PurchaseExample/PurchaseExample/Pro/ProGate.swift](Examples/PurchaseExample/PurchaseExample/Pro/ProGate.swift)

## The rules

The long form, with the reasons, is in the articles listed under [Documentation](#documentation).

| Rule | In short |
|---|---|
| Start once, at launch | Call `start(handling:)` from the app's root. Calling it again refreshes the store and replaces the handler. |
| One store per process | A second store listening for transaction updates in the same process logs a fault. |
| Delivery is at least once | The store finishes a transaction only after the handler returns. A throw, or a kill before finishing, means it is delivered again on the next `refresh()` or launch. |
| Delivery is one at a time | Handler calls never overlap. Each runs on the main actor after the previous delivery ends. |
| Be idempotent on `transaction.id` | Record what was delivered under the transaction's `id`, and save before returning. |
| Never call back into the store from the handler | From inside the handler, `refresh()` and `start` return without waiting for deliveries, and `purchase` throws `unsupported`. |
| Restore only from a button | `restore()` can ask the customer to sign in. Never call it from `start`, a `.task`, or a foreground hook. |
| No `.onInAppPurchaseCompletion` | StoreKit view purchases then arrive as transaction updates. Close a paywall when `isEntitled(to:)` changes. |
| Verification is strict | An unverified transaction is never delivered, counted, or finished, and a purchase that fails verification throws `unverified`. |
| Grace period counts as entitled | A subscription stays in `purchasedProductIDs` for as long as the App Store reports it current. |
| Non-renewing subscriptions are never owned | They reach the handler like a consumable; the app records and gates on the period itself. |
| Without a handler, consumables wait | `start()` finishes non-consumables and auto-renewables, leaves consumables and non-renewing subscriptions unfinished with a fault, and `purchase` of one throws `deliveryFailed`. |
| Gate bundles on their subscriptions | A bundle's own identifier never appears in `purchasedProductIDs`. |
| visionOS purchases need the scene | `purchase(_:options:)` is unavailable there. Purchase with `confirmIn:` a scene or through `@Environment(\.purchase)`, both from `InAppPurchaseUI`. |

## Example app

[Examples/PurchaseExample](Examples/PurchaseExample) sells tips, Pro as a one-time purchase or a
subscription, and consumable coins through one store and one handler. It shows a `StoreView` tip
jar, a `SubscriptionStoreView` paywall that closes on the entitlement change, a custom purchase
button, restore, refund handling, previews of every screen, and tests of its coin delivery with
`MockPurchaseClient`.

To run it, open `Examples/PurchaseExample/PurchaseExample.xcodeproj` in Xcode and run the
`PurchaseExample` scheme on an iOS simulator. The scheme loads products from the bundled
`Products.storekit`, so it needs no App Store Connect setup and no signing. To run on a device, set
your own development team on the target locally.

## Documentation

| Article | Covers |
|---|---|
| [Getting Started](Sources/InAppPurchase/InAppPurchase.docc/GettingStarted.md) | Add the package, create and start the store, gate a view. |
| [Delivering Transactions](Sources/InAppPurchase/InAppPurchase.docc/DeliveringTransactions.md) | The handler contract and each kind of product. |
| [Gating Features](Sources/InAppPurchase/InAppPurchase.docc/GatingFeatures.md) | Entitlements, grace periods, bundles, non-renewing subscriptions, restore. |
| [Handling Errors](Sources/InAppPurchase/InAppPurchase.docc/HandlingErrors.md) | `PurchaseError`, the codes an app acts on, load failures. |
| [Using the Store Outside SwiftUI](Sources/InAppPurchase/InAppPurchase.docc/UsingTheStoreOutsideSwiftUI.md) | Owning the store in a service, `Observations`, purchasing from UIKit or AppKit, loading before buying, testing an adapter. |
| [Building a Paywall](Sources/InAppPurchaseUI/InAppPurchaseUI.docc/BuildingAPaywall.md) | StoreKit views, custom purchase buttons, UIKit and AppKit, visionOS, refreshing on foreground. |
| [Testing Purchases](Sources/InAppPurchaseTesting/InAppPurchaseTesting.docc/TestingPurchases.md) | `MockPurchaseClient`, testing a handler, previews. |

## Products

| Product | Add it to |
|---|---|
| `InAppPurchase` | Any target that loads products, purchases, or reads entitlements. No UI framework behind it. |
| `InAppPurchaseUI` | A SwiftUI target that purchases through `@Environment(\.purchase)` or refreshes on foreground, or a UIKit or AppKit target that purchases with `purchase(_:confirmIn:options:)`. Depends on `InAppPurchase`. |
| `InAppPurchaseTesting` | A test target, or a target whose SwiftUI previews need `MockPurchaseClient`. Depends on `InAppPurchase`. |

## Requirements

- Swift 6.4 tools, Swift 6 language mode
- iOS 26 / Mac Catalyst 26 / macOS 26 / tvOS 26 / visionOS 26 / watchOS 26
- No dependencies

## Out of scope

Server-side validation, the App Store Server API, receipts, paywall design, and analytics.

## License

MIT. See [LICENSE](LICENSE).
