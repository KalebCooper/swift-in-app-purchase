import StoreKit
import Synchronization
import os

/// A ``PurchaseClient`` backed by StoreKit 2.
///
/// Every transaction it returns has passed StoreKit's verification. One that fails is logged and
/// dropped, never delivered or finished.
struct StoreKitPurchaseClient: PurchaseClient {
  /// The number of ``updates()`` streams still being consumed in this process. StoreKit delivers
  /// every update to every listener, so a second live stream means two stores handle, and may
  /// deliver, the same transaction.
  private static let liveUpdateStreams = Mutex(0)

  /// Returns a transaction for each product the customer is currently entitled to.
  func currentEntitlements() async -> [PurchaseTransaction] {
    await Self.verified(Transaction.currentEntitlements)
  }

  /// Finishes `transaction` with the App Store. A transaction not read from StoreKit has nothing to
  /// finish.
  func finish(_ transaction: PurchaseTransaction) async {
    await transaction.storeKitTransaction?.finish()
  }

  /// Loads the products with the given identifiers from the App Store.
  func products(for ids: [String]) async throws(PurchaseError) -> [PurchaseProduct] {
    do {
      return try await Product.products(for: ids).map { PurchaseProduct($0) }
    } catch {
      throw PurchaseError(converting: error)
    }
  }

  /// Starts a purchase of `product` with `options` and returns how it ended.
  ///
  /// A product not loaded from the App Store throws ``PurchaseError/Code/productUnavailable``. On
  /// visionOS a purchase needs the scene's purchaser; without one this throws
  /// ``PurchaseError/Code/invalidPresentationContext``.
  func purchase(
    _ product: PurchaseProduct,
    options: Set<Product.PurchaseOption>,
    purchaser: Purchaser?
  ) async throws(PurchaseError) -> PurchaseOutcome {
    guard let storeKitProduct = product.storeKitProduct else {
      throw PurchaseError(.productUnavailable)
    }
    let result = try await purchaseResult(
      of: storeKitProduct, options: options, purchaser: purchaser)
    switch result {
    case .pending:
      return .pending
    case .success(.unverified(_, let error)):
      throw PurchaseError(.unverified, underlying: error)
    case .success(.verified(let transaction)):
      return .success(PurchaseTransaction(transaction))
    case .userCancelled:
      return .userCancelled
    @unknown default:
      throw PurchaseError(.unknown)
    }
  }

  /// Syncs the customer's transactions with the App Store.
  func sync() async throws(PurchaseError) {
    do {
      try await AppStore.sync()
    } catch {
      throw PurchaseError(converting: error)
    }
  }

  /// Returns the transactions StoreKit holds unfinished.
  func unfinished() async -> [PurchaseTransaction] {
    await Self.verified(Transaction.unfinished)
  }

  /// Emits each transaction StoreKit delivers outside a purchase call.
  ///
  /// Ending the stream stops listening to StoreKit. Opening a second stream while another is live
  /// in the process logs a fault.
  func updates() -> AsyncStream<PurchaseTransaction> {
    let (stream, continuation) = AsyncStream.makeStream(of: PurchaseTransaction.self)
    let othersLive = Self.liveUpdateStreams.withLock { count in
      count += 1
      return count > 1
    }
    if othersLive {
      logger.fault(
        """
        More than one StoreKit transaction listener is running. Create one PurchaseStore for the \
        app and share it, or a transaction can reach more than one handler.
        """)
    }
    let listener = Task {
      for await result in Transaction.updates {
        if let transaction = Self.verified(result) { continuation.yield(transaction) }
      }
      continuation.finish()
    }
    continuation.onTermination = { _ in
      listener.cancel()
      Self.liveUpdateStreams.withLock { $0 -= 1 }
    }
    return stream
  }

  /// Runs the purchase through `purchaser`, or through StoreKit's own path where the platform has
  /// one.
  private func purchaseResult(
    of product: Product,
    options: Set<Product.PurchaseOption>,
    purchaser: Purchaser?
  ) async throws(PurchaseError) -> Product.PurchaseResult {
    do {
      if let purchaser { return try await purchaser(product, options) }
    } catch {
      throw PurchaseError(converting: error)
    }
    #if os(visionOS)
    // visionOS has no purchase that picks its own window; only the scene's `PurchaseAction` can.
    throw PurchaseError(.invalidPresentationContext)
    #else
    do {
      return try await product.purchase(options: options)
    } catch {
      throw PurchaseError(converting: error)
    }
    #endif
  }

  /// Returns the transaction in `result`, or `nil`, logged, if it failed verification.
  private static func verified(
    _ result: VerificationResult<Transaction>
  ) -> PurchaseTransaction? {
    switch result {
    case .unverified(let transaction, let error):
      logger.error(
        """
        Dropped transaction \(transaction.id) for \(transaction.productID, privacy: .public): \
        \(error.localizedDescription, privacy: .public)
        """)
      return nil
    case .verified(let transaction):
      return PurchaseTransaction(transaction)
    }
  }

  /// Returns the transactions in `transactions` that pass verification.
  private static func verified(_ transactions: Transaction.Transactions) async
    -> [PurchaseTransaction]
  {
    var verifiedTransactions: [PurchaseTransaction] = []
    for await result in transactions {
      if let transaction = verified(result) { verifiedTransactions.append(transaction) }
    }
    return verifiedTransactions
  }
}

extension PurchaseProduct {
  /// Reads `product`'s storefront presentation, keeping `product` as ``storeKitProduct``.
  fileprivate init(_ product: Product) {
    self.init(
      description: product.description,
      displayName: product.displayName,
      displayPrice: product.displayPrice,
      id: product.id,
      price: product.price,
      storeKitProduct: product,
      type: product.type
    )
  }
}

extension PurchaseTransaction {
  /// Reads `transaction`'s record, keeping `transaction` as ``storeKitTransaction``.
  fileprivate init(_ transaction: Transaction) {
    self.init(
      appAccountToken: transaction.appAccountToken,
      expirationDate: transaction.expirationDate,
      id: transaction.id,
      isUpgraded: transaction.isUpgraded,
      originalID: transaction.originalID,
      productID: transaction.productID,
      productType: transaction.productType,
      purchaseDate: transaction.purchaseDate,
      quantity: transaction.purchasedQuantity,
      revocationDate: transaction.revocationDate,
      storeKitTransaction: transaction
    )
  }
}

private let logger = Logger(subsystem: "InAppPurchase", category: "StoreKitPurchaseClient")
