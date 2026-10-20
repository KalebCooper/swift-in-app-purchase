# Gating Features

Unlock a feature for the customers who own any of the products that grant it.

## Overview

``PurchaseStore/purchasedProductIDs`` is the set of products the customer currently owns. An
``Entitlement`` names the products that unlock one feature, and ``PurchaseStore/isEntitled(to:)``
answers whether the customer owns any of them. The store is observable, so a view that asks
updates when the answer changes.

### Declare an entitlement

Declare each entitlement once, listing every product that unlocks the feature: a one-time purchase
and every subscription in the group, so an upgrade or a crossgrade keeps the feature unlocked.
From `Examples/PurchaseExample/PurchaseExample/Pro/Entitlement+Pro.swift`:

```swift
extension Entitlement {
  /// Pro is unlocked by the one-time purchase or by either subscription.
  static let pro = Entitlement(["pro.lifetime", "pro.monthly", "pro.yearly"])
}
```

Then gate on it with `store.isEntitled(to: .pro)`.

### What counts as owned

A product is in ``PurchaseStore/purchasedProductIDs`` while the App Store reports it as a current
entitlement and it has not been revoked or upgraded:

- A non-consumable, from purchase until the App Store refunds or revokes it.
- An auto-renewable subscription, for as long as the App Store reports it current. That includes a
  billing grace period, when the paid period has ended and the App Store is still retrying the
  renewal: a subscriber in grace keeps the feature.
- Not a subscription the customer upgraded away from. The subscription they upgraded to counts
  instead.
- Never a non-renewing subscription. See below.

A consumable is never in the set, even while the App Store lists it unfinished. It is something to
deliver, not to gate on: grant it in the transaction handler and gate on what the app recorded.

The set changes as subscriptions renew, expire, and are refunded. Renewals and refunds arrive as
transaction updates. Expiry arrives as nothing at all, so the store wakes itself at the earliest
expiration date ahead and reads the entitlements again. ``PurchaseStore/refresh()`` reads them
again too, which `refreshingPurchases(_:)` in `InAppPurchaseUI` calls whenever the app returns to
the foreground.

The store computes the set at start before anything that waits on the network, so a gated view is
right offline.

### Purchases awaiting approval

A purchase that needs approval, such as an Ask to Buy request, returns
``PurchaseOutcome/pending`` and grants nothing yet. Its product joins
``PurchaseStore/pendingProductIDs``, so a gated view can show that a request is waiting instead of
offering the purchase again:

```swift
if store.isEntitled(to: .pro) {
  ProFeatures()
} else if store.pendingProductIDs.contains("pro.lifetime") {
  Text("Waiting for approval")
} else {
  PaywallButton()
}
```

The product leaves the set when its transaction arrives, whether or not the handler delivers it,
or when the customer turns out to own it. A revocation does not touch the set.

The set is kept in memory only, because StoreKit cannot list the requests awaiting approval:

- A relaunch forgets every pending product. An approval after the relaunch still arrives as a
  transaction and reaches the handler as usual.
- A decline sends nothing, so a declined product stays pending until the app relaunches.
- Only purchases made through the store's own purchase methods are tracked. A purchase started in
  one of StoreKit's views, such as `StoreView`, never reports pending to the store, so its product
  never joins the set.

### Subscription bundles

Buying a subscription bundle creates one transaction per bundled subscription, so the bundle's own
product identifier never appears in ``PurchaseStore/purchasedProductIDs``. Gate on the bundled
subscriptions instead:

```swift
extension Entitlement {
  // "bundle.monthly" bundles these two. Its own ID is never in purchasedProductIDs.
  static let musicAndVideo = Entitlement(["music.monthly", "video.monthly"])
}
```

### Non-renewing subscriptions

The App Store does not say when a non-renewing subscription ends; the app decides. So the store
never counts one as owned. It delivers each to the transaction handler like a consumable, where the
app records the period it grants, for example from ``PurchaseTransaction/purchaseDate``, and gates
on that record rather than on an ``Entitlement``. See <doc:DeliveringTransactions>.

### Restore from a button only

Entitlements stay in sync on their own, so most customers never need to restore.
``PurchaseStore/restore()`` syncs with the App Store, which may ask the customer to sign in, then
recomputes and returns ``PurchaseStore/purchasedProductIDs``. Because it can show a sign-in prompt,
call it only from an explicit action such as a Restore button, never from `start`, a `.task`, or a
foreground hook. From `Examples/PurchaseExample/PurchaseExample/Pro/ProGate.swift`:

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

A customer who dismisses the sign-in prompt makes `restore()` throw
``PurchaseError/Code/userCancelled``, which an app can treat as nothing happening. See
<doc:HandlingErrors>.

### Preview each state

``PurchaseStore/preview(products:purchasedProductIDs:)`` reports the identifiers it is given as
owned, so a preview can show a gated view locked and unlocked:

```swift
#Preview("Unlocked") {
  ProGate()
    .environment(PurchaseStore.preview(purchasedProductIDs: ["pro.yearly"]))
}
```
