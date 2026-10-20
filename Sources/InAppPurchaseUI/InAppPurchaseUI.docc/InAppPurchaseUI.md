# ``InAppPurchaseUI``

SwiftUI, UIKit, and AppKit integration for a purchase store.

## Overview

``InAppPurchase/PurchaseStore/purchase(_:using:options:)`` purchases through SwiftUI's
`@Environment(\.purchase)`, and ``InAppPurchase/PurchaseStore/purchase(_:confirmIn:options:)``
confirms in a `UIScene`, a `UIViewController`, or an `NSWindow` the app names, so the confirmation
sheet appears where the customer is looking. On visionOS, where a purchase needs its scene, these
are the purchase paths. ``SwiftUICore/View/refreshingPurchases(_:)`` refreshes the store whenever
the scene becomes active.

For a ready-made storefront, use StoreKit's `StoreView`, `ProductView`, or `SubscriptionStoreView`.
Their purchases reach the store as transaction updates.

## Topics

### Essentials

- <doc:BuildingAPaywall>

### Purchasing

- ``InAppPurchase/PurchaseStore/purchase(_:using:options:)``
- ``InAppPurchase/PurchaseStore/purchase(_:confirmIn:options:)``

### Refreshing

- ``SwiftUICore/View/refreshingPurchases(_:)``
