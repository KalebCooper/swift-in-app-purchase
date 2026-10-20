# ``InAppPurchase``

Load products, make purchases, and track entitlements with StoreKit 2.

## Overview

``PurchaseStore`` is the observable state a view renders: the products on offer and what the
customer owns. It reads from the App Store in an app, or from the mock client in
`InAppPurchaseTesting` in a test or preview.

Start the store once at launch with a handler that delivers what the customer paid for. Every
transaction reaches the handler as a ``TransactionEvent``, one at a time, and the store finishes it
only after the handler returns. Ask whether the customer owns a feature with
``PurchaseStore/isEntitled(to:)`` and an ``Entitlement``.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:DeliveringTransactions>
- <doc:GatingFeatures>
- <doc:HandlingErrors>
- <doc:UsingTheStoreOutsideSwiftUI>

### State

- ``PurchaseStore``

### Purchasing

- ``Purchaser``

### Delivering and gating

- ``TransactionEvent``
- ``Entitlement``

### Values

- ``PurchaseError``
- ``PurchaseOutcome``
- ``PurchaseProduct``
- ``PurchaseTransaction``
