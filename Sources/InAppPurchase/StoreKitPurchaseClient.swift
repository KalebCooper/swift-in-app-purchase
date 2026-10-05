import StoreKit

/// A ``PurchaseClient`` backed by StoreKit 2.
public struct StoreKitPurchaseClient: PurchaseClient {
  /// Creates a client that reads from the App Store.
  public init() {}

  /// Returns a transaction for each product the customer is currently entitled to.
  public func currentEntitlements() async -> [PurchaseTransaction] {
    fatalError("StoreKitPurchaseClient.currentEntitlements() is not implemented.")
  }

  /// Finishes `transaction` with the App Store.
  public func finish(_ transaction: PurchaseTransaction) async {
    fatalError("StoreKitPurchaseClient.finish(_:) is not implemented.")
  }

  /// Loads the products with the given identifiers from the App Store.
  public func products(for identifiers: Set<String>) async throws(PurchaseError)
    -> [PurchaseProduct]
  {
    fatalError("StoreKitPurchaseClient.products(for:) is not implemented.")
  }

  /// Starts a purchase of `product` with `options` and returns how it ended.
  public func purchase(
    _ product: PurchaseProduct,
    options: Set<Product.PurchaseOption>
  ) async throws(PurchaseError) -> PurchaseOutcome {
    fatalError("StoreKitPurchaseClient.purchase(_:options:) is not implemented.")
  }

  /// Syncs the customer's transactions with the App Store.
  public func restore() async throws(PurchaseError) {
    fatalError("StoreKitPurchaseClient.restore() is not implemented.")
  }

  /// Emits each transaction StoreKit delivers outside a purchase call.
  public func transactionUpdates() -> AsyncStream<PurchaseTransaction> {
    fatalError("StoreKitPurchaseClient.transactionUpdates() is not implemented.")
  }
}
