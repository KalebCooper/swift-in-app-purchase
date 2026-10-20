# Delivering Transactions

Deliver what the customer paid for exactly once, even when a transaction reaches the app more
than once.

## Overview

Every transaction the store learns of goes through the one handler passed to
``PurchaseStore/start(handling:)``. That covers a purchase the app started, a transaction update
such as a renewal, a refund, an approved Ask to Buy request, or a purchase made in one of StoreKit's
own views, and a transaction an earlier launch left unfinished. The handler receives each as a
``TransactionEvent``: ``TransactionEvent/purchased(_:)`` to deliver its content, or
``TransactionEvent/revoked(_:)`` to take it back.

### The handler contract

**Delivery is at least once.** The store finishes a transaction only after the handler returns.
If the handler throws, the store logs the error, leaves the transaction unfinished, and delivers it
again on the next ``PurchaseStore/refresh()`` or launch. If the app is terminated after the handler
returns but before the transaction is finished, the next launch delivers it again. Within one run
of the app, a transaction the store has finished is not delivered again, and a copy that arrives
while the first is still queued joins it rather than running twice.

**Delivery is one at a time.** Handler invocations never overlap. Each runs on the main actor and
starts only after the previous delivery ends, whether its transaction was finished or its delivery
failed.

**The handler must be idempotent on `transaction.id`.** Because a transaction can arrive more than
once, record what was delivered under the transaction's ``PurchaseTransaction/id`` and do nothing
the second time. Save that record before returning: the store finishes the transaction as soon as
the handler returns, and StoreKit does not offer a finished transaction again.

Finishing only after delivery is what keeps a consumable from being lost. If the store finished
first and the app then failed to grant the coins, StoreKit would never offer that transaction
again.

### Consumables

A consumable has content only the app can grant, so the handler grants it and the store finishes
the transaction afterward. The example app records one grant per transaction and computes the
balance as the sum of the grants, so a redelivered purchase changes nothing and a refund removes
exactly what the purchase added. From
`Examples/PurchaseExample/PurchaseExample/Coins/CoinDelivery.swift`:

```swift
static func deliver(_ event: TransactionEvent, in context: ModelContext) throws {
  switch event {
  case .purchased(let transaction):
    // A transaction can arrive more than once, so grant its coins only the first time.
    guard try grants(for: transaction, in: context).isEmpty else { return }
    let coins = coinsPerPack[transaction.productID, default: 0] * transaction.quantity
    context.insert(CoinGrant(coins: coins, transactionID: transaction.id))
  case .revoked(let transaction):
    // A revocation carries the id of the purchase it revokes.
    for grant in try grants(for: transaction, in: context) {
      context.delete(grant)
    }
  }
  try context.save()
}
```

Multiply by ``PurchaseTransaction/quantity``: one transaction can buy several of a product.

### Revocations

When the App Store refunds or revokes a purchase, the transaction arrives again with the same
``PurchaseTransaction/id`` and a ``PurchaseTransaction/revocationDate``, as
``TransactionEvent/revoked(_:)``. The store tells it apart from the purchase it revokes, so both
reach the handler even in the same run. Take back what the purchase delivered, keyed on the same
`id`.

A revoked product is no longer in ``PurchaseStore/purchasedProductIDs``. For a non-consumable or a
subscription that is the whole effect, so the handler has nothing to do.

### Non-consumables and auto-renewable subscriptions

Owning one of these is its content: ``PurchaseStore/isEntitled(to:)`` reports it as soon as the
transaction is finished, and the store recomputes entitlements after every delivery. The handler
can return without doing anything, as the example app's `default` arm does for Pro.

### Non-renewing subscriptions

A non-renewing subscription reaches the handler like a consumable and is never in
``PurchaseStore/purchasedProductIDs``, because only the app knows how long one lasts. Record its
period in the handler, for example from ``PurchaseTransaction/purchaseDate``, and gate on that
record. See <doc:GatingFeatures>.

### Starting without a handler

``PurchaseStore/start()`` starts the store with no handler. A non-consumable or auto-renewable
subscription is then finished as soon as it arrives, since owning it is the content. A consumable
or non-renewing subscription is left unfinished and the store logs a fault, because nothing has
delivered what was paid for, and a purchase of one throws ``PurchaseError/Code/deliveryFailed``.
Those transactions are delivered once a handler is given through ``PurchaseStore/start(handling:)``.
An app that sells only consumables it does not need to track, such as tips, still passes a handler,
even one that returns immediately, so its transactions are finished.

### What the handler must not do

The handler must not call ``PurchaseStore/refresh()``, ``PurchaseStore/start()``,
``PurchaseStore/start(handling:)``, or a purchase method on the store. Each of those waits on the
delivery queue, and the handler's own delivery is at its head. The store guards against the
deadlock: from inside the handler, a refresh or a start recomputes entitlements and returns without
waiting for deliveries, and a purchase logs a fault and throws ``PurchaseError/Code/unsupported``.

### How a purchase returns

Every purchase method on the store, including the `InAppPurchaseUI` wrappers, returns
``PurchaseOutcome/success(_:)`` only after the handler delivered the transaction and the store
finished it, so ``PurchaseStore/purchasedProductIDs`` is already current when the call returns. If
the handler threw, the purchase throws ``PurchaseError/Code/deliveryFailed`` and the transaction is
delivered again on the next refresh or launch. The handler's own error is not carried in the
``PurchaseError``, because it need not be `Sendable`; log it in the handler.

A purchase that awaits approval returns ``PurchaseOutcome/pending``. When it is approved, the
transaction arrives as an update and goes through the handler like any other.

### One store per process

Create one ``PurchaseStore`` for the app and share it, for example through the SwiftUI environment.
Each started store runs its own transaction listener, its own delivery queue, and its own record of
the transactions it finished, so two stores in one process can each deliver the same transaction to
their own handler, and their handlers can run at the same time. A store that sells through the App
Store logs a fault when it starts while another is still listening for transaction updates.

### Verification

Verification is always strict. A transaction that fails StoreKit's verification is logged and
dropped: it is never delivered, never counted in ``PurchaseStore/purchasedProductIDs``, and never
finished. A purchase whose transaction fails verification throws
``PurchaseError/Code/unverified``.
