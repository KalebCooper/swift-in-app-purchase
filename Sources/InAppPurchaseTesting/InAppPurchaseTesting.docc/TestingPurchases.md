# Testing Purchases

Run a store against values a test sets, and test the app's transaction handler without the App
Store.

## Overview

``MockPurchaseClient`` stands in for the App Store. Create a store with it through
``InAppPurchase/PurchaseStore/init(client:productIDs:)``, set what the store should see, start the
store with the app's real handler, and check what the handler did and what the store finished.
Products and transactions are plain values a test constructs:
``/InAppPurchase/PurchaseProduct`` and ``/InAppPurchase/PurchaseTransaction``.

### Set what the store sees

Each property sets one answer the mock gives the store:

- ``MockPurchaseClient/entitlements``: the transactions the customer is entitled to, which become
  ``/InAppPurchase/PurchaseStore/purchasedProductIDs``.
- ``MockPurchaseClient/products`` and ``MockPurchaseClient/productsError``: what a product load
  returns or throws.
- ``MockPurchaseClient/purchaseResult`` and ``MockPurchaseClient/purchaseResults``: how a
  purchase ends, an outcome or an error, for every product or for one.
- ``MockPurchaseClient/syncResult``: how ``/InAppPurchase/PurchaseStore/restore()`` ends.
- ``MockPurchaseClient/unfinishedTransactions``: transactions waiting at launch, which the store
  delivers when it starts. Finishing one removes it.

The mock is `Sendable` and its state sits behind a lock, so a test sets and reads it from any task.

### Test the app's handler

Starting the store delivers every unfinished transaction and waits for those deliveries before it
returns, so a test can assert right after `start(handling:)`. From
`Examples/PurchaseExample/PurchaseExampleTests/CoinDeliveryTests.swift`:

```swift
@Test func deliversCoinsOnce() async throws {
  let container = try ModelContainer(
    for: CoinGrant.self,
    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
  )
  let mock = MockPurchaseClient()
  mock.unfinishedTransactions = [
    PurchaseTransaction(id: 1, productID: "coins.100", productType: .consumable)
  ]
  let store = PurchaseStore(client: mock, productIDs: ["coins.100"])

  await store.start { event in
    try CoinDelivery.deliver(event, in: container.mainContext)
  }

  #expect(try balance(in: container) == 100)
  #expect(mock.finishedTransactions.map(\.id) == [1])
}
```

``MockPurchaseClient/finishedTransactions`` lists every transaction the store finished, in order.
A transaction the handler threw on is not in it.

To test redelivery, start a second store on a fresh mock holding the same unfinished transaction,
as a relaunch after an interrupted finish would see it, and check that the handler granted nothing
more.

### Send transaction updates

``MockPurchaseClient/send(_:)`` delivers a transaction to a started store as StoreKit does for a
renewal, a refund, or an approved Ask to Buy request. A transaction sent before the store has
started reaches no stream but waits in ``MockPurchaseClient/unfinishedTransactions``, as one
waiting at launch does, so the store delivers it when it starts.

The mock keeps its ledger as StoreKit does, so a test sets up only the state before it acts. Every
transaction a purchase returns or ``MockPurchaseClient/send(_:)`` delivers joins
``MockPurchaseClient/unfinishedTransactions`` until the store finishes it. A revocation removes the
entitlement with its identifier from ``MockPurchaseClient/entitlements``. A non-consumable or
auto-renewable subscription replaces the entitlement for its product, as a renewal does, or joins
them. A consumable or non-renewing subscription leaves the entitlements as they are.

An update is delivered asynchronously, so wait for it with
``MockPurchaseClient/nextFinishedTransaction()`` rather than sleeping. Each call returns a
different finish in the order they happened, including finishes from before the call, so consume
the earlier ones first. From the same file:

```swift
@Test func revocationRemovesTheGrant() async throws {
  let container = try makeContainer()
  let mock = MockPurchaseClient()
  mock.unfinishedTransactions = [
    PurchaseTransaction(id: 1, productID: "coins.100", productType: .consumable)
  ]
  let store = PurchaseStore(client: mock, productIDs: ["coins.100"])
  await store.start { event in
    try CoinDelivery.deliver(event, in: container.mainContext)
  }
  _ = try await mock.nextFinishedTransaction()

  mock.send(
    PurchaseTransaction(
      id: 1,
      productID: "coins.100",
      productType: .consumable,
      revocationDate: Date()
    )
  )
  _ = try await mock.nextFinishedTransaction()

  #expect(try balance(in: container) == 0)
}
```

A transaction with a `revocationDate` reaches the handler as
``/InAppPurchase/TransactionEvent/revoked(_:)``.

### Test a purchase

Set ``MockPurchaseClient/purchaseResult`` to the outcome the App Store would give, then purchase.
On a store started with ``/InAppPurchase/PurchaseStore/start(handling:)``, a successful purchase
runs the handler and finishes the transaction before it returns:

```swift
mock.purchaseResult = .success(.success(transaction))
let outcome = try await store.purchase(product)
#expect(mock.finishedTransactions == [transaction])
```

Set it to `.failure(PurchaseError(.networkUnavailable))`, or any other code, to test how the app
reports an error. To end one product's purchase differently, set its entry in
``MockPurchaseClient/purchaseResults``:

```swift
mock.purchaseResults["pro.lifetime"] = .success(.pending)
```

``MockPurchaseClient/purchaseRequests`` records every purchase the store asked for, in order, with
its product and options. The mock ignores the `PurchaseAction` passed to
`purchase(_:using:options:)` from `InAppPurchaseUI`, so a store backed by it purchases the same
way from a view or a test; ``MockPurchaseClient/PurchaseRequest/usesPurchaser`` reports whether
one was passed.

### Preview

A SwiftUI preview needs no mock.
``/InAppPurchase/PurchaseStore/preview(products:purchasedProductIDs:)`` offers the given products,
reports the given identifiers as owned, and completes no purchase. From
`Examples/PurchaseExample/PurchaseExample/Pro/ProGate.swift`:

```swift
#Preview("Locked") {
  ProGate()
    .environment(
      PurchaseStore.preview(products: [
        PurchaseProduct(
          displayName: "Pro Lifetime",
          displayPrice: "$29.99",
          id: "pro.lifetime",
          type: .nonConsumable
        )
      ])
    )
}
```

Reach for the mock in a preview only when it must show a purchase completing or a transaction
arriving.
