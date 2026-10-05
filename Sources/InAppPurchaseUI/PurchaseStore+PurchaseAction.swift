import InAppPurchase
import StoreKit
import SwiftUI

extension PurchaseStore {
  /// Purchases `product` with `options` through `action`, the view's `@Environment(\.purchase)`, so
  /// the confirmation sheet appears in the scene the customer is looking at. Returns
  /// ``/InAppPurchase/PurchaseOutcome/success(_:)`` only after the handler delivered the
  /// transaction and it was finished.
  ///
  /// This is the purchase path on visionOS, where a purchase needs the scene's action. A store
  /// backed by `MockPurchaseClient` ignores `action`.
  ///
  /// ```swift
  /// @Environment(\.purchase) private var purchase
  ///
  /// Button("Buy") {
  ///   Task { _ = try? await store.purchase(product, using: purchase) }
  /// }
  /// ```
  ///
  /// - Throws: The same errors as ``/InAppPurchase/PurchaseStore/purchase(_:options:)``.
  public func purchase(
    _ product: PurchaseProduct,
    using action: PurchaseAction,
    options: Set<Product.PurchaseOption> = []
  ) async throws(PurchaseError) -> PurchaseOutcome {
    try await purchase(product, options: options) { product, options in
      try await action(product, options: options)
    }
  }
}
