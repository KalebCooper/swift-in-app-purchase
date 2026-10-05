# ``InAppPurchaseUI``

SwiftUI integration for a purchase store.

## Overview

``InAppPurchase/PurchaseStore/purchase(_:using:options:)`` purchases through SwiftUI's
`@Environment(\.purchase)`, which shows the confirmation sheet in the scene the customer is looking
at and is the only programmatic purchase path on visionOS.
``SwiftUICore/View/refreshingPurchases(_:)`` refreshes the store whenever the scene becomes active.

For a ready-made storefront, use StoreKit's `StoreView`, `ProductView`, or `SubscriptionStoreView`.
Their purchases reach the store as transaction updates.

## Topics

### Essentials

- <doc:BuildingAPaywall>

### Purchasing

- ``InAppPurchase/PurchaseStore/purchase(_:using:options:)``

### Refreshing

- ``SwiftUICore/View/refreshingPurchases(_:)``
