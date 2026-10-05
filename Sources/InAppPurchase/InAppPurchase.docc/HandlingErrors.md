# Handling Errors

Tell a failure the app can act on from one it can only report.

## Overview

Every throwing call on ``PurchaseStore`` throws ``PurchaseError``, so a `catch` block receives it
already typed. A purchase that ends without failing returns a ``PurchaseOutcome`` instead: a
cancelled purchase and one awaiting approval are outcomes, not errors.

### The error and its code

A ``PurchaseError`` has a ``PurchaseError/code`` that says what went wrong and an
``PurchaseError/underlying`` error that caused it. When StoreKit raised the failure, `underlying`
keeps StoreKit's `StoreKitError` or `Product.PurchaseError`, so a case this package does not name
on its own, such as an ineligible offer, can still be told apart. Two other errors are kept as
`underlying` too: a failed StoreKit verification maps to ``PurchaseError/Code/unverified``, and a
`CancellationError` maps to ``PurchaseError/Code/unknown``. An error of any other type maps to
``PurchaseError/Code/unknown`` with no underlying error, because it need not be `Sendable`.

``PurchaseError/Code`` is an open set of values rather than a closed enum, so a new code is not a
breaking change. A `switch` over it ends in a `default` arm:

```swift
do {
  _ = try await store.purchase(product, using: purchase)
} catch {
  switch error.code {
  case .deliveryFailed:
    message = "Paid, but delivery failed. It is retried the next time the app opens."
  case .networkUnavailable:
    message = "The App Store could not be reached. Try again later."
  default:
    message = "Purchase failed: \(error.code.rawValue)"
  }
}
```

A failed delivery is also retried each time the app returns to the foreground when a view uses
`refreshingPurchases(_:)` from `InAppPurchaseUI`, which calls ``PurchaseStore/refresh()`` whenever
the scene becomes active.

The example app's `Pro/PaywallButton.swift` handles a purchase's outcomes and errors in full.

An app or a test double can declare its own codes in an extension on ``PurchaseError/Code``.

### The codes an app acts on

- term ``PurchaseError/Code/userCancelled``: The customer cancelled. Only
  ``PurchaseStore/restore()`` throws it, when the customer dismisses the sign-in prompt; a cancelled
  purchase returns ``PurchaseOutcome/userCancelled`` instead. Treat it as nothing happening.
- term ``PurchaseError/Code/deliveryFailed``: The customer paid, but the transaction handler threw,
  or the store was started without a handler and the product is a consumable or non-renewing
  subscription. The transaction stays unfinished and is delivered again on the next
  ``PurchaseStore/refresh()`` or launch, so do not ask the customer to buy again. The handler's own
  error is not carried here; log it in the handler.
- term ``PurchaseError/Code/unverified``: The App Store returned a transaction that failed
  StoreKit's verification. Nothing was delivered or finished.
- term ``PurchaseError/Code/networkUnavailable``: The App Store could not be reached. Offer to try
  again later.
- term ``PurchaseError/Code/unsupported``: A purchase was started from inside the transaction
  handler, which the store refuses, or StoreKit reported the operation unsupported on this device.

The other codes describe the account, the storefront, or the App Store itself, such as
``PurchaseError/Code/purchaseNotAllowed`` or ``PurchaseError/Code/notAvailableInStorefront``.
Report them to the customer; ``PurchaseError/underlying`` carries the detail for a log.

### Purchase outcomes

``PurchaseStore/purchase(_:options:)`` returns one of three outcomes when it does not throw:

- term ``PurchaseOutcome/success(_:)``: The handler delivered the transaction and the store
  finished it. Entitlements are already updated.
- term ``PurchaseOutcome/pending``: The purchase awaits approval, such as an Ask to Buy request.
  When it is approved, the transaction arrives as an update and goes through the handler.
- term ``PurchaseOutcome/userCancelled``: The customer dismissed the purchase sheet.

### Loading products

Loading products does not throw. The store publishes the result instead:

- ``PurchaseStore/isLoadingProducts`` is `true` while a load is in progress.
- ``PurchaseStore/loadError`` holds why the last load failed, or `nil` once one succeeds.
  ``PurchaseStore/refresh()`` retries a failed load, so a view can show the error with a Try Again
  button that calls it.
- ``PurchaseStore/missingProductIDs`` lists the requested identifiers the App Store does not sell,
  as of the last successful load. ``PurchaseStore/products`` leaves them out. A missing identifier
  is usually a typo, a product not yet set up in App Store Connect, or one absent from the StoreKit
  configuration file the scheme runs with.
