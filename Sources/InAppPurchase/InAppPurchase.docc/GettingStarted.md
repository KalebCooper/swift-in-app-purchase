# Getting Started

Add the package, create one store, start it at launch, and gate a view on what the customer owns.

## Overview

An app holds one ``PurchaseStore`` for its whole life. It creates the store with the identifiers
of every product it sells, starts it once from the app's root with a handler that delivers what
the customer paid for, and puts it in the SwiftUI environment so any view can read the products on
offer and ask what the customer owns.

The snippets in this article are taken from the example app in `Examples/PurchaseExample`, which
sells tips, a Pro unlock, and consumable coins through one store and runs in the simulator against
a bundled StoreKit configuration.

### Add the package

Add the package to `Package.swift`, or through File > Add Package Dependencies in Xcode. No version
is tagged yet, so depend on the `main` branch; once the first release is tagged, switch to
`from:` that version.

```swift
dependencies: [
  .package(url: "https://github.com/KalebCooper/swift-in-app-purchase.git", branch: "main")
]
```

Add the products each target needs:

- `InAppPurchase` to any target that loads products, purchases, or reads entitlements. It imports
  no UI framework.
- `InAppPurchaseUI` to a SwiftUI target that purchases through `@Environment(\.purchase)` or
  refreshes the store when the app returns to the foreground.
- `InAppPurchaseTesting` to a test target, or a target whose SwiftUI previews need
  `MockPurchaseClient`.

```swift
.target(
  name: "MyApp",
  dependencies: [
    .product(name: "InAppPurchase", package: "swift-in-app-purchase"),
    .product(name: "InAppPurchaseUI", package: "swift-in-app-purchase"),
  ]
)
```

### Create one store

Create the store with ``PurchaseStore/init(productIDs:)``, listing every product the app sells.
``PurchaseStore/products`` keeps the order given here, and a repeated identifier is listed once.
Creating the store does no work; nothing reaches the App Store until the store is started.

```swift
@State private var store = PurchaseStore(productIDs: [
  "coins.100", "coins.500", "pro.lifetime", "pro.monthly", "pro.yearly", "tip.large",
  "tip.medium", "tip.small",
])
```

Create exactly one store and share it. StoreKit sends every transaction update to every listener,
so a second store listening in the same process could deliver the same transaction twice. The
store logs a fault when a second App Store listener starts.

### Start it at launch

Call ``PurchaseStore/start(handling:)`` once, from the app's root. The example app starts the store
in the root view's `.task` and routes each transaction to the code that delivers it:

```swift
var body: some Scene {
  WindowGroup {
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
  }
  .modelContainer(container)
}
```

Starting the store does four things, in this order, and then returns:

1. Starts listening for transaction updates, such as renewals, refunds, approved Ask to Buy
   requests, and purchases made in StoreKit's own views.
2. Computes ``PurchaseStore/purchasedProductIDs`` from the customer's current entitlements.
3. Delivers every transaction an earlier launch left unfinished.
4. Loads ``PurchaseStore/products``.

Entitlements come before anything that waits on the network, so a gated view shows the right state
even offline. Calling `start(handling:)` again replaces the handler and refreshes the store
without starting a second listener.

The handler has a contract: it may see a transaction more than once, it runs one transaction at a
time, and the store finishes the transaction only after it returns. <doc:DeliveringTransactions>
covers the contract and each kind of product.

### Put it in the environment

`.environment(store)` makes the store available to every view below the root. A view reads it
with `@Environment(PurchaseStore.self)`.

`refreshingPurchases(_:)`, from `InAppPurchaseUI`, calls ``PurchaseStore/refresh()`` each time the
app returns to the foreground, so a renewal, an expiry, a refund, or a transaction left unfinished is picked
up when the customer returns to the app. Attach it once, near the root, as above.

### Gate a view

Declare an ``Entitlement`` for each feature, listing every product that unlocks it:

```swift
extension Entitlement {
  /// Pro is unlocked by the one-time purchase or by either subscription.
  static let pro = Entitlement(["pro.lifetime", "pro.monthly", "pro.yearly"])
}
```

Then ask the store with ``PurchaseStore/isEntitled(to:)``. The store is observable, so the view
updates when a purchase, a renewal, an expiry, or a refund changes the answer. From
`Examples/PurchaseExample/PurchaseExample/Pro/ProGate.swift`:

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

<doc:GatingFeatures> covers subscriptions, grace periods, bundles, and restoring purchases.
<doc:HandlingErrors> covers what can go wrong while loading and purchasing.
