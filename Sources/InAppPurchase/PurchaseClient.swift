import StoreKit

/// Runs a StoreKit purchase in a presentation context the app chooses, such as a scene, a view
/// controller, a window, or SwiftUI's `PurchaseAction`, so the confirmation sheet appears where
/// the customer is looking.
///
/// Pass one to ``PurchaseStore/purchase(_:using:options:)``. `InAppPurchaseUI` builds one for each
/// context StoreKit can confirm in; build your own only for a context it does not cover.
///
/// ```swift
/// let purchaser = Purchaser { product, options in
///   try await product.purchase(confirmIn: scene, options: options)
/// }
/// ```
public struct Purchaser: Sendable {
  /// Purchases the product with the options and returns StoreKit's result. Runs on the main actor
  /// because every StoreKit purchase that names a context does.
  package let purchase:
    @MainActor @Sendable (Product, Set<Product.PurchaseOption>) async throws
      -> Product.PurchaseResult

  /// Creates a purchaser that runs `purchase` for each purchase.
  ///
  /// - Parameter purchase: Purchases the product with the options in the context of your choice
  ///   and returns StoreKit's result. Throw StoreKit's error as is; the store maps it to a
  ///   ``PurchaseError``.
  public init(
    _ purchase:
      @escaping @MainActor @Sendable (Product, Set<Product.PurchaseOption>) async throws
      -> Product.PurchaseResult
  ) {
    self.purchase = purchase
  }
}

/// The seam between purchase state and the store that fulfils it.
///
/// `StoreKitPurchaseClient` talks to the App Store and `MockPurchaseClient` answers from values a
/// test sets. The protocol is package-scoped so its requirements can follow StoreKit without
/// breaking anyone outside the package. Products and transactions cross it as ``PurchaseProduct``
/// and ``PurchaseTransaction`` because StoreKit offers no way to construct its own outside a store
/// session. Every transaction a client returns has passed verification.
package protocol PurchaseClient: Sendable {
  /// Returns a transaction for each product the customer is currently entitled to.
  func currentEntitlements() async -> [PurchaseTransaction]

  /// Tells the store the app has delivered what `transaction` paid for. Until then, the store keeps
  /// it in ``unfinished()`` and delivers it again.
  func finish(_ transaction: PurchaseTransaction) async

  /// Loads the products with the given identifiers. An identifier the store does not sell is left
  /// out rather than thrown, and the result's order is not guaranteed.
  func products(for ids: [String]) async throws(PurchaseError) -> [PurchaseProduct]

  /// Purchases `product` with `options` through `purchaser`, or through the client's own path when
  /// `purchaser` is `nil`, and returns how it ended. A completed purchase is not finished.
  func purchase(
    _ product: PurchaseProduct,
    options: Set<Product.PurchaseOption>,
    purchaser: Purchaser?
  ) async throws(PurchaseError) -> PurchaseOutcome

  /// Syncs the customer's transactions with the store, prompting for authentication.
  func sync() async throws(PurchaseError)

  /// Returns the transactions the app has not finished.
  func unfinished() async -> [PurchaseTransaction]

  /// Emits each transaction that arrives outside a purchase call, such as a renewal, a refund, an
  /// approved Ask to Buy request, or a purchase on another device.
  func updates() -> AsyncStream<PurchaseTransaction>
}
