import InAppPurchase
import StoreKit

// Each witness spells out `@MainActor`: a witness for a nonisolated protocol requirement is
// otherwise inferred nonisolated and loses access to the class's state.

/// A ``InAppPurchase/PurchaseClient`` that answers every call from values a test sets.
///
/// The mock's state is main-actor isolated, so a test reads and sets it directly.
@MainActor
public final class MockPurchaseClient: PurchaseClient {
  /// The transactions returned by ``currentEntitlements()``.
  public var entitlements: [PurchaseTransaction]
  /// The error thrown by every throwing call, or `nil` to succeed.
  public var failure: PurchaseError?
  /// The transactions passed to ``finish(_:)``, in call order.
  public private(set) var finished: [PurchaseTransaction] = []
  /// The outcome returned by ``purchase(_:options:)``.
  public var outcome: PurchaseOutcome
  /// The products returned by ``products(for:)``.
  public var products: [PurchaseProduct]

  /// Creates a mock that owns `entitlements`, sells `products`, and returns `outcome` from a
  /// purchase, or throws `failure` from every throwing call.
  public init(
    entitlements: [PurchaseTransaction] = [],
    failure: PurchaseError? = nil,
    outcome: PurchaseOutcome = .cancelled,
    products: [PurchaseProduct] = []
  ) {
    self.entitlements = entitlements
    self.failure = failure
    self.outcome = outcome
    self.products = products
  }

  /// Returns ``entitlements``.
  @MainActor public func currentEntitlements() async -> [PurchaseTransaction] {
    entitlements
  }

  /// Records `transaction` in ``finished``.
  @MainActor public func finish(_ transaction: PurchaseTransaction) async {
    finished.append(transaction)
  }

  /// Throws ``failure`` if set, and otherwise returns ``products``.
  @MainActor public func products(for identifiers: Set<String>) async throws(PurchaseError)
    -> [PurchaseProduct]
  {
    if let failure { throw failure }
    return products
  }

  /// Throws ``failure`` if set, and otherwise returns ``outcome``.
  @MainActor public func purchase(
    _ product: PurchaseProduct,
    options: Set<Product.PurchaseOption>
  ) async throws(PurchaseError) -> PurchaseOutcome {
    if let failure { throw failure }
    return outcome
  }

  /// Throws ``failure`` if set.
  @MainActor public func restore() async throws(PurchaseError) {
    if let failure { throw failure }
  }

  /// Returns a stream that finishes without emitting.
  nonisolated public func transactionUpdates() -> AsyncStream<PurchaseTransaction> {
    AsyncStream { $0.finish() }
  }
}
