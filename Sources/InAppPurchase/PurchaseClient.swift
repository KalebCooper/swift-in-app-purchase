import StoreKit

/// The seam between purchase state and the store that fulfils it.
///
/// ``StoreKitPurchaseClient`` talks to the App Store through StoreKit 2. A test or preview passes
/// the mock client from `InAppPurchaseTesting` instead, and an app can conform its own client, an
/// actor or a struct as readily as a class. Products and transactions cross the protocol as
/// ``PurchaseProduct`` and ``PurchaseTransaction`` because StoreKit offers no way to construct its
/// own outside a store session.
public protocol PurchaseClient: Sendable {
  /// Returns a transaction for each product the customer is currently entitled to.
  func currentEntitlements() async -> [PurchaseTransaction]

  /// Tells the store the app has delivered what `transaction` paid for. Until then, the store
  /// delivers the transaction again through ``transactionUpdates()``.
  func finish(_ transaction: PurchaseTransaction) async

  /// Loads the products with the given identifiers from the store.
  func products(for identifiers: Set<String>) async throws(PurchaseError) -> [PurchaseProduct]

  /// Starts a purchase of `product` with `options` and returns how it ended. A completed purchase
  /// is not finished; call ``finish(_:)`` once its content is delivered.
  func purchase(
    _ product: PurchaseProduct,
    options: Set<Product.PurchaseOption>
  ) async throws(PurchaseError) -> PurchaseOutcome

  /// Syncs the customer's transactions with the App Store, prompting for authentication.
  func restore() async throws(PurchaseError)

  /// Emits each transaction that arrives outside a purchase call, such as a renewal, a refund, an
  /// approved Ask to Buy request, or a purchase on another device.
  func transactionUpdates() -> AsyncStream<PurchaseTransaction>
}
