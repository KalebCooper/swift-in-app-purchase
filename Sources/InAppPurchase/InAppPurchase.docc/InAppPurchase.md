# ``InAppPurchase``

Load products, make purchases, and track entitlements with StoreKit 2.

## Overview

``PurchaseStore`` is the observable state a view renders. It drives a ``PurchaseClient``:
``StoreKitPurchaseClient`` in an app, or the mock client from `InAppPurchaseTesting` in a test or
preview.

## Topics

### State

- ``PurchaseStore``

### Clients

- ``PurchaseClient``
- ``StoreKitPurchaseClient``
- ``VerificationPolicy``

### Values

- ``PurchaseError``
- ``PurchaseOutcome``
- ``PurchaseProduct``
- ``PurchaseTransaction``
