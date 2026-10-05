# ``InAppPurchaseUI``

SwiftUI integration for a purchase store.

## Overview

A purchase started from a view goes through SwiftUI's `@Environment(\.purchase)`, which shows the
confirmation sheet in the scene the customer is looking at and is the only purchase path on
visionOS. ``InAppPurchase/PurchaseStore/purchase(_:using:options:)`` routes it through the store,
so the transaction is delivered and finished like any other.

``SwiftUICore/View/refreshingPurchases(_:)`` refreshes the store whenever the scene becomes active.

For a ready-made storefront, use StoreKit's `StoreView`, `ProductView`, or `SubscriptionStoreView`.
Their purchases reach the store as transaction updates.

## Topics

### Purchasing

- ``InAppPurchase/PurchaseStore/purchase(_:using:options:)``

### Refreshing

- ``SwiftUICore/View/refreshingPurchases(_:)``
