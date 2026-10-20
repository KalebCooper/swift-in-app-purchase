# Building a Paywall

Sell through StoreKit's views or your own, in SwiftUI, UIKit, or AppKit, and keep the store current
while the app runs.

## Overview

A paywall can use StoreKit's ready-made views, `StoreView`, `ProductView`, and
`SubscriptionStoreView`, or the app's own views over ``/InAppPurchase/PurchaseStore/products``.
Either way, every purchase reaches the store's transaction handler, which delivers it, and the
store finishes it afterward.

The snippets in this article are taken from the example app in `Examples/PurchaseExample`.

### Sell with StoreKit's views

A purchase made in a StoreKit view arrives as a transaction update, which the store delivers to
the app's handler like any other transaction. Do not attach `.onInAppPurchaseCompletion`: it takes
the purchase off that path. From `Examples/PurchaseExample/PurchaseExample/Tips/TipJarScreen.swift`:

```swift
NavigationStack {
  // A purchase made in StoreView arrives as a transaction update, which the store delivers to
  // the app's handler. Attaching .onInAppPurchaseCompletion would take it off that path.
  StoreView(ids: ["tip.small", "tip.medium", "tip.large"])
    .safeAreaInset(edge: .top) {
      if !thankedTransactionIDs.isEmpty {
        Text("Thank you for ^[\(thankedTransactionIDs.count) tip](inflect: true)!")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding()
          .background(.thinMaterial)
      }
    }
    .navigationTitle("Tips")
}
```

### Dismiss on an entitlement change

To close a paywall after a purchase, watch the entitlement rather than the purchase. When the
handler has delivered the transaction and the store has finished it,
``/InAppPurchase/PurchaseStore/isEntitled(to:)`` changes and the sheet closes. From
`Examples/PurchaseExample/PurchaseExample/Pro/ProGate.swift`:

```swift
.sheet(isPresented: $isShowingSubscriptions) {
  SubscriptionStoreView(productIDs: ["pro.monthly", "pro.yearly"])
}
// Close the sheet when the entitlement changes, not in .onInAppPurchaseCompletion. Without
// that modifier, a purchase made in the sheet reaches the store as a transaction update.
.onChange(of: store.isEntitled(to: .pro)) { _, isEntitled in
  if isEntitled { isShowingSubscriptions = false }
}
```

### Build your own purchase button

For a paywall built from the app's own views, read a product from the store and purchase it with
``InAppPurchase/PurchaseStore/purchase(_:using:options:)``, passing the view's
`@Environment(\.purchase)`. The confirmation sheet then appears in the scene the customer is
looking at. The call returns ``/InAppPurchase/PurchaseOutcome/success(_:)`` only after the handler
delivered the transaction and the store finished it, so the entitlement is already current. From
`Examples/PurchaseExample/PurchaseExample/Pro/PaywallButton.swift`:

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

A purchase cancelled through the sheet returns ``/InAppPurchase/PurchaseOutcome/userCancelled``
rather than throwing, so the `.userCancelled` error arm is a safeguard, not a path the App Store
takes. A ``/InAppPurchase/PurchaseError/Code/deliveryFailed`` error means the customer paid and the
store will deliver again on the next refresh or launch. A purchase StoreKit recorded but reported
as cancelled or failed, as it can when the app leaves the foreground while StoreKit's own
confirmation is on screen, is delivered and returns ``/InAppPurchase/PurchaseOutcome/success(_:)``.

### Purchase from UIKit or AppKit

Outside SwiftUI, there is no purchase action to pass. Purchase with
`purchase(_:confirmIn:options:)` instead, naming the `UIScene`,
`UIViewController`, or `NSWindow` the confirmation sheet should appear in. The app picks the
context; the scene holding the view that started the purchase is the usual choice:

```swift
guard let scene = view.window?.windowScene else { return }
let outcome = try await store.purchase(product, confirmIn: scene)
```

The outcomes and errors are the same as for the purchase action above. For a context the package
does not cover, build an ``/InAppPurchase/Purchaser`` around the StoreKit call and pass it to
``/InAppPurchase/PurchaseStore/purchase(_:using:options:)``.

### visionOS

On visionOS a purchase needs its scene, so ``/InAppPurchase/PurchaseStore/purchase(_:options:)``
is unavailable there. Purchase through ``InAppPurchase/PurchaseStore/purchase(_:using:options:)``
from a SwiftUI view, or `purchase(_:confirmIn:options:)` with the
scene from UIKit. Purchases made through StoreKit's own views need nothing extra.

### Refresh when the app returns

``SwiftUICore/View/refreshingPurchases(_:)`` calls ``/InAppPurchase/PurchaseStore/refresh()``
whenever the scene becomes active. A refresh delivers transactions left unfinished, recomputes
entitlements, and retries a product load that failed, so a renewal, an expiry, a refund, or a
delivery that failed earlier is picked up when the customer comes back to the app.

The first appearance does not refresh, because starting the store already did that work. A refresh
under way runs to completion even if the scene leaves the active phase, so a delivery is never
abandoned partway. Attach the modifier once, near the root of the scene. From
`Examples/PurchaseExample/PurchaseExample/PurchaseExampleApp.swift`:

```swift
ContentView(thankedTransactionIDs: thankedTransactionIDs)
  .environment(store)
  .refreshingPurchases(store)
```
