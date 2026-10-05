# ``InAppPurchase``

Load products, make purchases, and track entitlements with StoreKit 2.

## Overview

``PurchaseStore`` is the observable state a view renders: the products on offer and what the
customer owns. It reads from the App Store in an app, or from the mock client in
`InAppPurchaseTesting` in a test or preview.

Call ``PurchaseStore/start(handling:)`` once at launch. The store then listens for transaction
updates, retries transactions left unfinished, and keeps ``PurchaseStore/purchasedProductIDs``
current. Every transaction reaches the handler at least once, one at a time, as a
``TransactionEvent``, and the store finishes it only after the handler returns, so the handler
must be idempotent on the transaction's `id`.

Ask whether the customer owns a feature with ``PurchaseStore/isEntitled(to:)`` and an
``Entitlement``. A subscription in a billing grace period counts as owned.

## Topics

### State

- ``PurchaseStore``

### Delivering and gating

- ``TransactionEvent``
- ``Entitlement``

### Values

- ``PurchaseError``
- ``PurchaseOutcome``
- ``PurchaseProduct``
- ``PurchaseTransaction``
