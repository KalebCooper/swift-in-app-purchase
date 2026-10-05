import Observation
import StoreKit

/// The observable purchase state a view renders: the products on offer and what the customer owns.
///
/// The store owns no StoreKit objects. It drives a ``PurchaseClient`` and publishes what the client
/// reports, so the same store runs against ``StoreKitPurchaseClient`` in an app and against a mock
/// in a test or preview.
@MainActor
@Observable
public final class PurchaseStore {
  /// A transaction for each product the customer is currently entitled to.
  public private(set) var entitlements: [PurchaseTransaction] = []
  /// Every product loaded so far, by identifier. Each call to ``loadProducts(_:)`` adds to it, so
  /// separate surfaces can load separate products through one store.
  public private(set) var products: [String: PurchaseProduct] = [:]

  @ObservationIgnored private let client: any PurchaseClient

  /// Creates a store that reads and purchases through `client`.
  public init(client: any PurchaseClient) {
    self.client = client
  }

  /// Finishes `transaction` once its content is delivered, and refreshes ``entitlements``.
  public func finish(_ transaction: PurchaseTransaction) async {
    fatalError("PurchaseStore.finish(_:) is not implemented.")
  }

  /// Hands each transaction from ``PurchaseClient/transactionUpdates()`` to `deliver` and refreshes
  /// ``entitlements``, until the calling task is cancelled. `deliver` grants the transaction's
  /// content and calls ``finish(_:)``. Call this from a long-lived task, such as the app scene's
  /// `.task`.
  public func listenForTransactionUpdates(
    _ deliver: (PurchaseTransaction) async -> Void
  ) async {
    fatalError("PurchaseStore.listenForTransactionUpdates(_:) is not implemented.")
  }

  /// Loads the products with the given identifiers, adds them to ``products``, and returns them.
  @discardableResult
  public func loadProducts(_ identifiers: Set<String>) async throws(PurchaseError)
    -> [PurchaseProduct]
  {
    fatalError("PurchaseStore.loadProducts(_:) is not implemented.")
  }

  /// Purchases `product` with `options` and refreshes ``entitlements`` when it completes. A
  /// completed purchase is not finished; deliver its content, then call ``finish(_:)``.
  public func purchase(
    _ product: PurchaseProduct,
    options: Set<Product.PurchaseOption> = []
  ) async throws(PurchaseError) -> PurchaseOutcome {
    fatalError("PurchaseStore.purchase(_:options:) is not implemented.")
  }

  /// Syncs with the store and refreshes ``entitlements``.
  public func restore() async throws(PurchaseError) {
    fatalError("PurchaseStore.restore() is not implemented.")
  }
}
