# Using the Store Outside SwiftUI

Own the store in an app-wide service, observe it from a view model, and purchase from UIKit or
AppKit.

## Overview

``PurchaseStore`` is an `@Observable` class isolated to the main actor, and nothing in it depends
on SwiftUI. A service layer, a coordinator, or a view model can own it, observe it, and purchase
through it the same way a view does.

### Own one store

Create the store once, at launch, in whatever owns the app's long-lived services, such as an app
delegate or a dependency container. Start it once with ``PurchaseStore/start(handling:)`` and
share that one instance. Never create a store per screen or per view model: StoreKit sends every
transaction update to every listener, so a second store could deliver the same transaction twice.
A store backed by the App Store logs a fault when a second listener starts in the process.

```swift
@MainActor
final class AppServices {
  let store = PurchaseStore(productIDs: ["pro.lifetime", "pro.monthly"])

  func launch() async {
    await store.start { event in
      // Deliver the content once per transaction.id, and save before returning.
    }
  }
}
```

``PurchaseStore/start(handling:)`` returns once it has computed entitlements, retried the
transactions left unfinished, and loaded the products, and the transaction listener keeps running
after it returns. It starts the listener before anything that can wait, so call it as early in
launch as the handler can run. Calling it again refreshes the store and replaces the handler without
starting a second listener. Releasing the store stops its listener, so keep it for the life of the
app.

### Refresh when the app returns

The listener receives what StoreKit pushes, but expiry, a delivery that failed earlier, and a
product load that failed send nothing. Call ``PurchaseStore/refresh()`` each time the app returns to
the foreground. In SwiftUI, `refreshingPurchases(_:)` from `InAppPurchaseUI` does this. Elsewhere,
observe the app entering the foreground:

```swift
@MainActor
final class AppServices {
  let store = PurchaseStore(productIDs: ["pro.lifetime", "pro.monthly"])
  private var foregroundObserver: (any NSObjectProtocol)?

  func launch() async {
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: .main
    ) { [store] _ in
      Task { @MainActor in await store.refresh() }
    }
    await store.start { event in
      // Deliver the content once per transaction.id, and save before returning.
    }
  }
}
```

Observe `willEnterForegroundNotification` rather than `didBecomeActiveNotification`: a system alert
or sheet, such as StoreKit's own purchase confirmation, makes the app resign and regain active
without leaving the foreground, and a refresh then would run in the middle of the purchase. A
refresh that overlaps a purchase is redundant rather than harmful, because a transaction is
delivered once however many paths find it. AppKit has no foreground notification, so observe
`NSApplication.didBecomeActiveNotification` there. Never call ``PurchaseStore/restore()`` from such a
hook: it can ask the customer to sign in.

### Observe the store

Observe the store's state with `Observations` from the Observation framework. It yields the
current value first, then a new value after each change:

```swift
@MainActor
final class ProStatus {
  private(set) var isPro = false
  private var observation: Task<Void, Never>?

  init(store: PurchaseStore) {
    observation = Task { [weak self] in
      let changes = Observations { store.purchasedProductIDs }
      for await purchased in changes {
        self?.isPro = purchased.contains("pro.lifetime")
      }
    }
  }

  isolated deinit {
    observation?.cancel()
  }
}
```

Changes made in the same turn of the main actor arrive as one value, so a value can skip an
intermediate state but is never older than the latest change. The sequence ends when the task
iterating it is cancelled, which is why the class cancels the task when it goes away.

The same shape works for any of the store's state: ``PurchaseStore/pendingProductIDs`` to show a
purchase awaiting approval, ``PurchaseStore/products`` once they load, or
``PurchaseStore/loadError`` to offer a retry.

### Purchase from UIKit or AppKit

`InAppPurchaseUI` adds `purchase(_:confirmIn:options:)`, which confirms the purchase in a
`UIScene`, near a `UIViewController`, or in an `NSWindow`. The app picks the context. A service
with no view of its own can use the scene the customer is looking at, its foreground-active
`UIWindowScene`:

```swift
func buy(_ product: PurchaseProduct) async throws(PurchaseError) -> PurchaseOutcome? {
  let scene = UIApplication.shared.connectedScenes
    .compactMap { $0 as? UIWindowScene }
    .first { $0.activationState == .foregroundActive }
  guard let scene else { return nil }
  return try await store.purchase(product, confirmIn: scene)
}
```

The `buy(_:)` above returns `nil` when no scene is active. Otherwise it returns the same outcomes and
throws the same errors as ``PurchaseStore/purchase(_:options:)``, which is unavailable on visionOS,
where a purchase needs its scene. For a context `InAppPurchaseUI` does not cover, build a
``Purchaser`` around the StoreKit purchase call and pass it to
``PurchaseStore/purchase(_:using:options:)``.

### Buy a product that is not loaded yet

``PurchaseStore/products`` holds the products from the last successful load. A purchase that
starts from a link or a notification can arrive before the first load ends, or after it failed. Look
the product up with ``PurchaseStore/product(id:)`` first, then load with
``PurchaseStore/loadProducts()``, which joins a load already running instead of starting another,
and search what it returns:

```swift
func product(id: String) async throws(PurchaseError) -> PurchaseProduct? {
  if let product = store.product(id: id) { return product }
  return try await store.loadProducts().first { $0.id == id }
}
```

A `nil` result means the App Store does not sell that product, or the store was not created with
its identifier, so treat it as unavailable. A thrown error means the load failed; see
<doc:HandlingErrors>.

### Wrap the store for view model tests

The package has no store protocol of its own. A view model that depends on the store directly gets
its state from a real store, so to test the view model with a fake, put the store behind a protocol
of the app's own and adapt the store to it:

```swift
@MainActor
protocol ProAccess {
  var isPro: Bool { get }
  var isAwaitingApproval: Bool { get }
}

@MainActor
struct StoreProAccess: ProAccess {
  let store: PurchaseStore

  var isPro: Bool { store.isEntitled(to: .pro) }
  var isAwaitingApproval: Bool { store.pendingProductIDs.contains("pro.lifetime") }
}
```

Here `.pro` is the ``Entitlement`` declared in <doc:GatingFeatures>. Test the view model against a
fake `ProAccess`, and test the adapter itself against a real store backed by `MockPurchaseClient`,
which `InAppPurchaseTesting` provides with `PurchaseStore(client:productIDs:)`:

```swift
@Test func ownsProOnceTheLifetimeUnlockIsOwned() async {
  let mock = MockPurchaseClient()
  mock.entitlements = [
    PurchaseTransaction(id: 1, productID: "pro.lifetime", productType: .nonConsumable)
  ]
  let store = PurchaseStore(client: mock, productIDs: ["pro.lifetime"])
  await store.start()

  #expect(StoreProAccess(store: store).isPro)
}
```
