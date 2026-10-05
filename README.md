# swift-in-app-purchase

[![CI](https://github.com/KalebCooper/swift-in-app-purchase/actions/workflows/ci.yml/badge.svg)](https://github.com/KalebCooper/swift-in-app-purchase/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

In-app purchases for Swift apps, built on StoreKit 2.

`PurchaseStore` is the observable state a view renders: the products on offer and what the customer
owns. It listens for transaction updates, retries transactions left unfinished, keeps entitlements
current as subscriptions renew, expire, and are refunded, and finishes a transaction only after your
code has delivered it. It reads from the App Store in an app and from `MockPurchaseClient` in a test
or preview.

> **Status:** pre-release. The store, the App Store client, the SwiftUI bridge, and the mock client
> are implemented and the store is tested against the mock client. No version has been tagged.

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

## How it works

Create one store with the identifiers of the products you sell, start it once at launch, and put it
in the environment.

```swift
import InAppPurchase
import SwiftUI

@main
struct ExampleApp: App {
  @State private var store = PurchaseStore(productIDs: ["tip.small", "tip.large"])

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(store)
        .task {
          await store.start { event in
            // Deliver what the customer paid for. See the recipes below.
          }
        }
    }
  }
}
```

`start(handling:)` starts the transaction listener, computes `purchasedProductIDs`, retries
transactions left unfinished by an earlier launch, and loads `products`, in that order, so gating
works before the network answers.

### The rules

- **Start once, at launch.** Call `start` or `start(handling:)` from your app's root. Calling it again
  refreshes the store and, if you pass a handler, replaces the handler.
- **One store per process.** A second store listening for transaction updates in the same process
  logs a fault.
- **Delivery is at least once, one at a time.** Every transaction, whether it came from a purchase,
  a transaction update such as an Ask to Buy approval, or an earlier launch, reaches your handler as
  `TransactionEvent.purchased` or `TransactionEvent.revoked`. Invocations never overlap, and the store
  finishes a transaction only after the handler returns. If the handler throws, or the app is killed
  before the transaction is finished, the transaction is delivered again on the next `refresh()` or
  launch. Make the handler idempotent on `transaction.id`.
- **The handler must not call `refresh()`, `start`, or `purchase` on the store.** Its own delivery is
  at the head of the queue those calls wait on. From inside the handler a refresh returns without
  waiting for deliveries, and a purchase throws `PurchaseError.Code.unsupported`.
- **Restore only from a button.** `restore()` can ask the customer to sign in. Never call it from
  `start`, a `.task`, or a foreground hook.
- **Do not attach `.onInAppPurchaseCompletion`.** Without it, purchases made through `StoreView`,
  `ProductView`, and `SubscriptionStoreView` arrive as transaction updates, which the store already
  delivers. To close a paywall after a purchase, dismiss it when `isEntitled(to:)` changes.
- **Verification is strict.** A transaction that fails StoreKit's verification is never delivered,
  counted, or finished, and a purchase that fails it throws `PurchaseError.Code.unverified`.
- **A subscription in a billing grace period counts as entitled.** `purchasedProductIDs` holds a
  subscription for as long as the App Store reports it current.
- **Non-renewing subscriptions are never in `purchasedProductIDs`**, because only the app knows how
  long one lasts. They reach the handler like a consumable.
- **With no handler, consumables and non-renewing subscriptions stay unfinished.** `start()` finishes
  a non-consumable or auto-renewable as soon as it arrives, since owning it is the content. It leaves
  a consumable or non-renewing subscription unfinished and logs a fault, and `purchase` of one throws
  `PurchaseError.Code.deliveryFailed`. Pass a handler to `start(handling:)` to deliver them.
- **Subscription bundles.** Buying a bundle creates one transaction per bundled subscription, so a
  bundle's own product ID never appears in `purchasedProductIDs`. Gate on the bundled subscriptions'
  product IDs.
- **visionOS.** `PurchaseStore.purchase(_:options:)` is unavailable there. Purchase through
  `purchase(_:using:options:)` from `InAppPurchaseUI`, which takes the scene's `PurchaseAction`.
  Purchases made through StoreKit's own views need nothing.

## Recipes

### A tip jar

StoreKit's `StoreView` is the storefront. The store delivers each tip. A tip has nothing to grant, so
the handler thanks the customer once per transaction.

```swift
import InAppPurchase
import StoreKit
import SwiftUI

@main
struct TipApp: App {
  @State private var store = PurchaseStore(productIDs: ["tip.small", "tip.medium", "tip.large"])
  @State private var thanked: Set<UInt64> = []

  var body: some Scene {
    WindowGroup {
      TipJarScreen()
        .environment(store)
        .task {
          await store.start { event in
            guard case .purchased(let transaction) = event else { return }
            // The same transaction can arrive more than once, so key on its id.
            guard thanked.insert(transaction.id).inserted else { return }
            // Show a thank-you, or record the tip.
          }
        }
    }
  }
}

struct TipJarScreen: View {
  var body: some View {
    StoreView(ids: ["tip.small", "tip.medium", "tip.large"])
  }
}
```

A tip is a consumable, so the store leaves it unfinished until the handler returns. If you do not
need to react to tips, a handler that returns immediately is enough to have them finished.

### Gating a feature behind a subscription

Declare the entitlement once. It is the set of products that each unlock the feature.

```swift
import InAppPurchase
import InAppPurchaseUI
import StoreKit
import SwiftUI

extension Entitlement {
  static let pro = Entitlement(["pro.monthly", "pro.yearly", "pro.lifetime"])
}

struct ProGate: View {
  @Environment(PurchaseStore.self) private var store
  @State private var isShowingPaywall = false

  var body: some View {
    Group {
      if store.isEntitled(to: .pro) {
        ProContent()
      } else {
        Button("Unlock Pro") { isShowingPaywall = true }
      }
    }
    .refreshingPurchases(store)
    .sheet(isPresented: $isShowingPaywall) {
      SubscriptionStoreView(productIDs: ["pro.monthly", "pro.yearly"])
        .storeButton(.visible, for: .restorePurchases)
        // Dismiss when the entitlement changes, not through .onInAppPurchaseCompletion.
        .onChange(of: store.isEntitled(to: .pro)) { _, isEntitled in
          if isEntitled { isShowingPaywall = false }
        }
    }
  }
}
```

`refreshingPurchases(_:)` calls `refresh()` each time the scene becomes active. Subscription renewals,
expiry, and refunds update `isEntitled(to:)` without any further code. A subscriber in a billing grace
period stays entitled.

To build your own paywall rather than use `SubscriptionStoreView`, read `store.products` and purchase
through the view's `PurchaseAction`:

```swift
struct PaywallButton: View {
  @Environment(PurchaseStore.self) private var store
  @Environment(\.purchase) private var purchase
  let product: PurchaseProduct

  var body: some View {
    Button("\(product.displayName) \(product.displayPrice)") {
      Task {
        switch try? await store.purchase(product, using: purchase) {
        case .success: break  // The entitlement is already updated.
        case .pending: break  // Approval later arrives as an update.
        case .userCancelled, nil: break
        }
      }
    }
  }
}
```

Gate a subscription bundle on the bundled subscriptions, not on the bundle:

```swift
extension Entitlement {
  // "bundle.monthly" bundles these two. Its own ID is never in purchasedProductIDs.
  static let musicAndVideo = Entitlement(["music.monthly", "video.monthly"])
}
```

### Consumable coins

Coins are a consumable, so the handler grants them and the store finishes the transaction afterward.
Key the grant on `transaction.id` so a redelivery changes nothing, and handle `.revoked` so a refund
takes the coins back.

```swift
import InAppPurchase
import SwiftData

@Model
final class CoinGrant {
  @Attribute(.unique) var transactionID: UInt64
  var coins: Int

  init(transactionID: UInt64, coins: Int) {
    self.transactionID = transactionID
    self.coins = coins
  }
}

let coinsPerPack = ["coins.100": 100, "coins.500": 500]

@MainActor
func deliver(_ event: TransactionEvent, in context: ModelContext) throws {
  switch event {
  case .purchased(let transaction):
    let id = transaction.id
    let existing = try context.fetch(
      FetchDescriptor<CoinGrant>(predicate: #Predicate { $0.transactionID == id })
    )
    guard existing.isEmpty else { return }  // Already delivered. Finishing was interrupted.
    let coins = coinsPerPack[transaction.productID, default: 0] * transaction.quantity
    context.insert(CoinGrant(transactionID: id, coins: coins))
    try context.save()

  case .revoked(let transaction):
    // A revocation carries the purchase's id.
    let id = transaction.id
    for grant in try context.fetch(
      FetchDescriptor<CoinGrant>(predicate: #Predicate { $0.transactionID == id })
    ) {
      context.delete(grant)
    }
    try context.save()
  }
}
```

Pass it to the store from the app's root:

```swift
await store.start { event in
  try deliver(event, in: container.mainContext)
}
```

The balance is the sum of the grants, so a redelivered purchase and a refund both leave it correct.
If `deliver` throws, the store leaves the transaction unfinished and delivers it again on the next
`refresh()` or launch. `purchase` then throws `PurchaseError.Code.deliveryFailed`; log the underlying
error in the handler, because the store does not carry it.

## Testing and previews

`InAppPurchaseTesting` provides `MockPurchaseClient`. Set what the store should see, then drive it
without the App Store.

```swift
import InAppPurchase
import InAppPurchaseTesting
import Testing

@MainActor
@Test func grantsCoinsOnce() async {
  let mock = MockPurchaseClient()
  mock.unfinishedTransactions = [
    PurchaseTransaction(id: 1, productID: "coins.100", productType: .consumable)
  ]
  let store = PurchaseStore(client: mock, productIDs: ["coins.100"])

  var delivered: [UInt64] = []
  await store.start { event in
    if case .purchased(let transaction) = event { delivered.append(transaction.id) }
  }

  #expect(delivered == [1])
  #expect(mock.finishedTransactions.map(\.id) == [1])
}
```

- `entitlements`, `products`, `productsError`, `purchaseResult`, `syncResult`, and
  `unfinishedTransactions` set what the mock answers.
- `send(_:)` delivers a transaction update to a started store.
- `finishedTransactions` lists what the store finished, and `nextFinishedTransaction()` waits for the
  next one, so a test never sleeps.

A SwiftUI preview uses `PurchaseStore.preview(products:purchasedProductIDs:)`, which needs neither
the mock nor the App Store.

```swift
#Preview {
  ProGate()
    .environment(
      PurchaseStore.preview(
        products: [
          PurchaseProduct(
            displayName: "Pro Monthly",
            displayPrice: "$4.99",
            id: "pro.monthly",
            type: .autoRenewable
          )
        ],
        purchasedProductIDs: []
      )
    )
}
```

Pass `purchasedProductIDs: ["pro.monthly"]` to preview the unlocked state. A preview store completes no
purchase.

## Out of scope

Server-side validation, the App Store Server API, receipts, paywall design, and analytics.

## License

MIT. See [LICENSE](LICENSE).
