# ``InAppPurchaseTesting``

A purchase client for tests and previews.

## Overview

``MockPurchaseClient`` answers every purchase call from values a test sets, so a
``/InAppPurchase/PurchaseStore`` runs without the App Store. Create the store with
``/InAppPurchase/PurchaseStore/init(client:productIDs:)``, set what it should see, and push
transaction updates into it with ``MockPurchaseClient/send(_:)``.

For a SwiftUI preview that needs no mock, use
``/InAppPurchase/PurchaseStore/preview(products:purchasedProductIDs:)``.

## Topics

### Clients

- ``MockPurchaseClient``

### Stores

- ``/InAppPurchase/PurchaseStore/init(client:productIDs:)``
