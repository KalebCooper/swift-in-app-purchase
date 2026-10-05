import StoreKit

/// A client that answers from fixed values, behind `PurchaseStore.preview(products:purchasedProductIDs:)`.
///
/// It sells `products`, reports one non-consumable entitlement per purchased identifier so a
/// started preview store keeps them, completes no purchase, and emits no updates.
struct PreviewPurchaseClient: PurchaseClient {
  let entitlements: [PurchaseTransaction]
  let products: [PurchaseProduct]

  init(products: [PurchaseProduct], purchasedProductIDs: [String]) {
    self.products = products
    entitlements = purchasedProductIDs.enumerated().map { offset, id in
      PurchaseTransaction(id: UInt64(offset + 1), productID: id, productType: .nonConsumable)
    }
  }

  func currentEntitlements() async -> [PurchaseTransaction] {
    entitlements
  }

  func finish(_ transaction: PurchaseTransaction) async {}

  func products(for ids: [String]) async throws(PurchaseError) -> [PurchaseProduct] {
    let requested = Set(ids)
    return products.filter { requested.contains($0.id) }
  }

  func purchase(
    _ product: PurchaseProduct,
    options: Set<Product.PurchaseOption>,
    purchaser: Purchaser?
  ) async throws(PurchaseError) -> PurchaseOutcome {
    .userCancelled
  }

  func sync() async throws(PurchaseError) {}

  func unfinished() async -> [PurchaseTransaction] {
    []
  }

  func updates() -> AsyncStream<PurchaseTransaction> {
    AsyncStream { $0.finish() }
  }
}
