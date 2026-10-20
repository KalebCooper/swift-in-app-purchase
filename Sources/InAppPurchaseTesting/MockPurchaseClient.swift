import InAppPurchase
import StoreKit
import Synchronization

/// A purchase client that answers every call from values a test sets.
///
/// Pass the mock to `PurchaseStore(client:productIDs:)` to run a store without the App Store.
/// Set what the store should see, push transactions into it with ``send(_:)``, and read what it
/// finished from ``finishedTransactions`` or await the next finish with
/// ``nextFinishedTransaction()``.
///
/// The mock keeps its ledger as StoreKit does. A transaction a purchase returns or ``send(_:)``
/// delivers stays in ``unfinishedTransactions`` until the store finishes it, and changes
/// ``entitlements``: a revocation removes the entitlement with its identifier, and a
/// non-consumable or auto-renewable subscription replaces the entitlement for its product or
/// joins them.
///
/// The mock is `Sendable` and its state sits behind a lock, so a test sets and reads it from any
/// task without hopping actors.
public final class MockPurchaseClient: PurchaseClient, Sendable {
  /// One purchase the store asked the mock to make.
  public struct PurchaseRequest: Sendable {
    /// The purchase options the store passed, such as a quantity or an app account token.
    public let options: Set<Product.PurchaseOption>

    /// The product the store asked to purchase.
    public let product: PurchaseProduct

    /// Whether the store passed a `Purchaser` to confirm the purchase in a context of the app's
    /// choosing, as `purchase(_:using:options:)` and `purchase(_:confirmIn:options:)` do.
    public let usesPurchaser: Bool
  }

  private typealias FinishWaiter = CheckedContinuation<
    Result<PurchaseTransaction, CancellationError>, Never
  >

  private struct State {
    var entitlements: [PurchaseTransaction] = []
    var finishWaiters: [Int: FinishWaiter] = [:]
    var finishedTransactions: [PurchaseTransaction] = []
    var nextToken = 0
    var products: [PurchaseProduct] = []
    var productsError: PurchaseError?
    var purchaseRequests: [PurchaseRequest] = []
    var purchaseResult: Result<PurchaseOutcome, PurchaseError> = .success(.userCancelled)
    var purchaseResults: [String: Result<PurchaseOutcome, PurchaseError>] = [:]
    var syncResult: Result<Void, PurchaseError> = .success(())
    var unfinishedTransactions: [PurchaseTransaction] = []
    var unreturnedFinishes: [PurchaseTransaction] = []
    var updateContinuations: [Int: AsyncStream<PurchaseTransaction>.Continuation] = [:]

    mutating func makeToken() -> Int {
      defer { nextToken += 1 }
      return nextToken
    }

    /// Applies `transaction` to the ledger as the App Store would on issuing it.
    mutating func record(_ transaction: PurchaseTransaction) {
      if transaction.revocationDate != nil {
        entitlements.removeAll { $0.id == transaction.id }
      } else if transaction.productType == .nonConsumable
        || transaction.productType == .autoRenewable
      {
        // A renewal is a new transaction for the same product. It replaces the entitlement it
        // renews rather than standing beside it, as StoreKit reports one per product.
        let index = entitlements.firstIndex { $0.productID == transaction.productID }
        entitlements.removeAll { $0.productID == transaction.productID }
        entitlements.insert(transaction, at: index ?? entitlements.endIndex)
      }
      if let index = unfinishedTransactions.firstIndex(where: { $0.id == transaction.id }) {
        unfinishedTransactions[index] = transaction
      } else {
        unfinishedTransactions.append(transaction)
      }
    }
  }

  private let state = Mutex(State())

  /// Creates a mock that owns nothing, sells nothing, and reports every purchase as cancelled.
  public init() {}

  // MARK: Values a test sets

  /// The transactions the customer is entitled to. Empty by default.
  ///
  /// A successful purchase or a sent transaction of a non-consumable or auto-renewable
  /// subscription replaces the entitlement for its product or joins them, and a sent revocation
  /// removes the entitlement with its identifier.
  public var entitlements: [PurchaseTransaction] {
    get { state.withLock { $0.entitlements } }
    set { state.withLock { $0.entitlements = newValue } }
  }

  /// The products the store sells. A request returns the ones whose identifiers it asked for, in
  /// the order set here rather than the order requested, as StoreKit does. Empty by default.
  public var products: [PurchaseProduct] {
    get { state.withLock { $0.products } }
    set { state.withLock { $0.products = newValue } }
  }

  /// The error a product request throws, or `nil` to return ``products``. `nil` by default.
  public var productsError: PurchaseError? {
    get { state.withLock { $0.productsError } }
    set { state.withLock { $0.productsError = newValue } }
  }

  /// How a purchase ends when ``purchaseResults`` has no entry for its product: an outcome to
  /// return or an error to throw. Returns ``/InAppPurchase/PurchaseOutcome/userCancelled`` by
  /// default.
  public var purchaseResult: Result<PurchaseOutcome, PurchaseError> {
    get { state.withLock { $0.purchaseResult } }
    set { state.withLock { $0.purchaseResult = newValue } }
  }

  /// How a purchase of each product ends, by product identifier. A product with no entry ends
  /// with ``purchaseResult``. Empty by default.
  public var purchaseResults: [String: Result<PurchaseOutcome, PurchaseError>] {
    get { state.withLock { $0.purchaseResults } }
    set { state.withLock { $0.purchaseResults = newValue } }
  }

  /// How every sync with the store ends. Succeeds by default.
  public var syncResult: Result<Void, PurchaseError> {
    get { state.withLock { $0.syncResult } }
    set { state.withLock { $0.syncResult = newValue } }
  }

  /// The transactions the app has not finished, such as purchases waiting at launch. A successful
  /// purchase or a sent transaction joins them, and finishing a transaction removes it. Empty by
  /// default.
  public var unfinishedTransactions: [PurchaseTransaction] {
    get { state.withLock { $0.unfinishedTransactions } }
    set { state.withLock { $0.unfinishedTransactions = newValue } }
  }

  // MARK: What the store did

  /// Every transaction finished so far, in the order it was finished.
  public var finishedTransactions: [PurchaseTransaction] {
    state.withLock { $0.finishedTransactions }
  }

  /// Every purchase the store asked for, in the order it asked, including those that threw.
  public var purchaseRequests: [PurchaseRequest] {
    state.withLock { $0.purchaseRequests }
  }

  /// The number of transaction-update streams still open.
  package var activeUpdateSubscriptions: Int {
    state.withLock { $0.updateContinuations.count }
  }

  /// Returns the next finished transaction, waiting for it if it has not happened yet.
  ///
  /// Each call returns a different finish, in the order they happened, so a finish that lands
  /// before the call is not missed and none is returned twice.
  ///
  /// - Throws: `CancellationError` if the calling task is cancelled while it waits.
  public func nextFinishedTransaction() async throws(CancellationError) -> PurchaseTransaction {
    let token = state.withLock { $0.makeToken() }
    let result = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        // Registration and the cancellation check share the lock, so a cancellation either sees
        // the waiter and resumes it, or happened first and is caught here.
        let immediate: Result<PurchaseTransaction, CancellationError>? = state.withLock { state in
          if !state.unreturnedFinishes.isEmpty {
            return .success(state.unreturnedFinishes.removeFirst())
          }
          if Task.isCancelled { return .failure(CancellationError()) }
          state.finishWaiters[token] = continuation
          return nil
        }
        if let immediate { continuation.resume(returning: immediate) }
      }
    } onCancel: {
      state.withLock { $0.finishWaiters.removeValue(forKey: token) }?
        .resume(returning: .failure(CancellationError()))
    }
    return try result.get()
  }

  // MARK: Driving the store

  /// Delivers `transaction` to every open transaction-update stream, as StoreKit does for a
  /// renewal, a refund, or an approved Ask to Buy request.
  ///
  /// The transaction updates ``entitlements`` and joins ``unfinishedTransactions`` before any
  /// stream receives it. A transaction sent while no stream is open reaches no stream, but waits
  /// in ``unfinishedTransactions`` until the store finishes it, as one waiting at launch does.
  public func send(_ transaction: PurchaseTransaction) {
    let continuations = state.withLock { state in
      state.record(transaction)
      return Array(state.updateContinuations.values)
    }
    for continuation in continuations {
      continuation.yield(transaction)
    }
  }

  // MARK: PurchaseClient

  package func currentEntitlements() async -> [PurchaseTransaction] {
    entitlements
  }

  package func finish(_ transaction: PurchaseTransaction) async {
    let waiter: FinishWaiter? = state.withLock { state in
      state.finishedTransactions.append(transaction)
      state.unfinishedTransactions.removeAll { $0.id == transaction.id }
      guard let token = state.finishWaiters.keys.min() else {
        state.unreturnedFinishes.append(transaction)
        return nil
      }
      return state.finishWaiters.removeValue(forKey: token)
    }
    waiter?.resume(returning: .success(transaction))
  }

  package func products(for ids: [String]) async throws(PurchaseError) -> [PurchaseProduct] {
    let (products, error) = state.withLock { ($0.products, $0.productsError) }
    if let error { throw error }
    let requested = Set(ids)
    return products.filter { requested.contains($0.id) }
  }

  package func purchase(
    _ product: PurchaseProduct,
    options: Set<Product.PurchaseOption>,
    purchaser: Purchaser?
  ) async throws(PurchaseError) -> PurchaseOutcome {
    let request = PurchaseRequest(
      options: options,
      product: product,
      usesPurchaser: purchaser != nil
    )
    let result = state.withLock { state in
      state.purchaseRequests.append(request)
      let result = state.purchaseResults[product.id] ?? state.purchaseResult
      if case .success(.success(let transaction)) = result {
        state.record(transaction)
      }
      return result
    }
    return try result.get()
  }

  package func sync() async throws(PurchaseError) {
    try syncResult.get()
  }

  package func unfinished() async -> [PurchaseTransaction] {
    unfinishedTransactions
  }

  package func updates() -> AsyncStream<PurchaseTransaction> {
    let (stream, continuation) = AsyncStream.makeStream(of: PurchaseTransaction.self)
    let token = state.withLock { $0.makeToken() }
    continuation.onTermination = { [weak self] _ in
      self?.state.withLock { _ = $0.updateContinuations.removeValue(forKey: token) }
    }
    state.withLock { $0.updateContinuations[token] = continuation }
    return stream
  }
}

extension PurchaseStore {
  /// Creates a store that sells the products with `productIDs` through `client`, for a test or a
  /// preview.
  public convenience init(client: MockPurchaseClient, productIDs: [String]) {
    self.init(client: client as any PurchaseClient, productIDs: productIDs)
  }
}
