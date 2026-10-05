import StoreKit

/// A ``PurchaseClient`` backed by StoreKit 2.
struct StoreKitPurchaseClient: PurchaseClient {
  /// Returns a transaction for each product the customer is currently entitled to.
  func currentEntitlements() async -> [PurchaseTransaction] {
    fatalError("StoreKitPurchaseClient.currentEntitlements() is not implemented.")
  }

  /// Finishes `transaction` with the App Store.
  func finish(_ transaction: PurchaseTransaction) async {
    fatalError("StoreKitPurchaseClient.finish(_:) is not implemented.")
  }

  /// Loads the products with the given identifiers from the App Store.
  func products(for ids: [String]) async throws(PurchaseError) -> [PurchaseProduct] {
    fatalError("StoreKitPurchaseClient.products(for:) is not implemented.")
  }

  /// Starts a purchase of `product` with `options` and returns how it ended.
  func purchase(
    _ product: PurchaseProduct,
    options: Set<Product.PurchaseOption>,
    purchaser: Purchaser?
  ) async throws(PurchaseError) -> PurchaseOutcome {
    fatalError("StoreKitPurchaseClient.purchase(_:options:purchaser:) is not implemented.")
  }

  /// Syncs the customer's transactions with the App Store.
  func sync() async throws(PurchaseError) {
    fatalError("StoreKitPurchaseClient.sync() is not implemented.")
  }

  /// Returns the transactions StoreKit holds unfinished.
  func unfinished() async -> [PurchaseTransaction] {
    fatalError("StoreKitPurchaseClient.unfinished() is not implemented.")
  }

  /// Emits each transaction StoreKit delivers outside a purchase call.
  func updates() -> AsyncStream<PurchaseTransaction> {
    fatalError("StoreKitPurchaseClient.updates() is not implemented.")
  }
}
