import Foundation
import Observation
import StoreKit
import os

/// Waits for `duration`. The store's expiry timer sleeps through this so a test can drive it.
package typealias Sleep = @Sendable (Duration) async throws -> Void

/// The observable purchase state a view renders: the products on offer and what the customer owns.
///
/// The store owns no StoreKit objects. It publishes what its client reports, so the same store
/// runs against the App Store in an app and against `MockPurchaseClient` in a test or preview.
///
/// Call ``start()`` or ``start(handling:)`` once at launch. From then on every transaction the
/// store learns of, whether from a purchase, a transaction update, or one left unfinished by an
/// earlier launch, goes through one handler, one at a time, and is finished only after the handler
/// returns. A transaction whose handler threw is delivered again on the next ``refresh()`` or
/// launch, so the handler must be idempotent on the transaction's `id`.
///
/// ```swift
/// @main
/// struct ExampleApp: App {
///   @State private var store = PurchaseStore(productIDs: ["pro.lifetime", "pro.monthly"])
///
///   var body: some Scene {
///     WindowGroup {
///       ContentView()
///         .environment(store)
///         .task { await store.start { event in /* Deliver the content. */ } }
///     }
///   }
/// }
/// ```
@MainActor
@Observable
public final class PurchaseStore {
  /// Whether a product load is in progress. Loads that overlap share one request, so this is
  /// `true` from the first call until the shared load ends.
  public private(set) var isLoadingProducts = false
  /// Why the last product load failed, or `nil` if it succeeded or has not run. It is kept while a
  /// retry runs and cleared when a load succeeds. ``refresh()`` retries a failed load, and
  /// ``loadProducts()`` retries on demand.
  public private(set) var loadError: PurchaseError?
  /// The requested product identifiers the store does not sell, as of the last successful load.
  /// ``refresh()`` loads again while any identifier is missing.
  public private(set) var missingProductIDs: Set<String> = []
  /// The identifiers of the products whose purchase awaits approval, such as an Ask to Buy
  /// request.
  ///
  /// A product joins when a purchase through ``purchase(_:options:)`` or
  /// ``purchase(_:using:options:)`` returns ``PurchaseOutcome/pending``, and leaves when a
  /// transaction for it arrives, whether or not its delivery succeeds, or when the customer is
  /// found to own it. A revocation leaves the set as it is.
  ///
  /// The set is kept in memory only, because StoreKit cannot list the requests awaiting approval.
  /// A relaunch forgets them, and an approval still arrives as a transaction. A decline sends
  /// nothing, so a declined product stays in the set until the app relaunches. A purchase started
  /// in one of StoreKit's views, such as `StoreView`, never reports pending to the store, so its
  /// product never joins.
  public private(set) var pendingProductIDs: Set<String> = []
  /// The products on offer, in the order their identifiers were given, as of the last successful
  /// load. A failed load leaves them as they were.
  public private(set) var products: [PurchaseProduct] = []
  /// The identifiers of the products the customer currently owns: purchases that are not revoked
  /// or upgraded, and subscriptions the store still reports as current, which includes one in a
  /// billing grace period. Non-renewing subscriptions are left out, because only the app knows how
  /// long one lasts.
  public private(set) var purchasedProductIDs: Set<String> = []

  private typealias Handler = @MainActor (TransactionEvent) async throws -> Void

  /// Tells a purchase and its revocation apart: a revocation arrives with the purchase's `id`.
  private struct DeliveryKey: Hashable {
    let id: UInt64
    let revocationDate: Date?

    init(_ transaction: PurchaseTransaction) {
      id = transaction.id
      revocationDate = transaction.revocationDate
    }
  }

  /// Whether the current task is inside the handler. A call back into the store from there must not
  /// wait on the delivery queue, because the handler's own delivery is at its head.
  @TaskLocal private static var isDelivering = false

  @ObservationIgnored private let client: any PurchaseClient
  /// Keys of every transaction finished in this process, so a replay is not delivered twice.
  @ObservationIgnored private var deliveredKeys: Set<DeliveryKey> = []
  /// Deliveries queued or running, by key. A key is added before its first suspension point so a
  /// duplicate arriving meanwhile is merged into it.
  @ObservationIgnored private var deliveries: [DeliveryKey: Task<Bool, Never>] = [:]
  /// Rises on every recompute so a slow older one cannot overwrite a newer result.
  @ObservationIgnored private var entitlementGeneration = 0
  @ObservationIgnored private var expiryTask: Task<Void, Never>?
  @ObservationIgnored private var handler: Handler?
  @ObservationIgnored private var isStarted = false
  @ObservationIgnored private var listenerTask: Task<Void, Never>?
  /// The newest purchase finished in this process for each product, so a purchase whose call ended
  /// without a transaction can find one the updates stream delivered meanwhile.
  @ObservationIgnored private var newestFinishedPurchases: [String: PurchaseTransaction] = [:]
  @ObservationIgnored private let productIDs: [String]
  /// The product load in flight. The store owns it, so a cancelled caller cannot cut it short, and
  /// every caller while it runs awaits it instead of starting another.
  @ObservationIgnored private var productLoad:
    Task<Result<[PurchaseProduct], PurchaseError>, Never>?
  /// The last delivery queued. The next one runs after it, so handlers never overlap.
  @ObservationIgnored private var queueTail: Task<Bool, Never>?
  /// The newest entitlement read. The store owns it, so a cancelled caller cannot cut it short.
  @ObservationIgnored private var recomputeTask: Task<Void, Never>?
  @ObservationIgnored private let sleep: Sleep

  /// Creates a store that sells the products with `productIDs` through the App Store. It does no
  /// work until ``start()`` or ``start(handling:)``.
  public convenience init(productIDs: [String]) {
    self.init(client: StoreKitPurchaseClient(), productIDs: productIDs)
  }

  /// Creates a store that sells the products with `productIDs` through `client`, and waits for
  /// subscription expiry through `sleep`.
  package init(
    client: any PurchaseClient,
    productIDs: [String],
    sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
  ) {
    self.client = client
    var seen: Set<String> = []
    self.productIDs = productIDs.filter { seen.insert($0).inserted }
    self.sleep = sleep
  }

  /// Stops listening for transaction updates and waiting for subscription expiry.
  isolated deinit {
    listenerTask?.cancel()
    expiryTask?.cancel()
    productLoad?.cancel()
    recomputeTask?.cancel()
  }

  // MARK: Reading

  /// Whether the customer owns any of the products that unlock `entitlement`.
  public func isEntitled(to entitlement: Entitlement) -> Bool {
    !entitlement.productIDs.isDisjoint(with: purchasedProductIDs)
  }

  /// The loaded product with identifier `id`, or `nil` if it is not loaded.
  public func product(id: String) -> PurchaseProduct? {
    products.first { $0.id == id }
  }

  // MARK: Starting

  /// Starts the store with no handler. Calling it again is harmless.
  ///
  /// Starts listening for transaction updates, computes ``purchasedProductIDs``, retries
  /// transactions left unfinished, loads ``products``, then returns. Entitlements are computed
  /// before anything that can wait on the network, so gating works offline.
  ///
  /// With no handler, a non-consumable or auto-renewable subscription is finished as soon as it
  /// arrives, because owning it is the content. A consumable or non-renewing subscription is left
  /// unfinished and logged as a fault, since nothing has delivered what it paid for; it is
  /// delivered once a handler is given through ``start(handling:)``.
  public func start() async {
    await begin(handler: nil)
  }

  /// Starts the store with `handler`, which delivers each transaction's content. Calling it again
  /// replaces the handler and refreshes without starting a second listener.
  ///
  /// Every transaction, whether from a purchase, a transaction update, or an earlier launch,
  /// reaches `handler` once as ``TransactionEvent/purchased(_:)`` or
  /// ``TransactionEvent/revoked(_:)``, and is finished only after `handler` returns. Invocations
  /// never overlap. If `handler` throws, the transaction stays unfinished and is delivered again
  /// on the next ``refresh()`` or launch, so `handler` must be idempotent on the transaction's
  /// `id`. Otherwise the store behaves as ``start()`` describes.
  ///
  /// ```swift
  /// await store.start { event in
  ///   switch event {
  ///   case .purchased(let transaction):
  ///     // Grant the content once per transaction.id, and save before returning.
  ///     try grant(transaction)
  ///   case .revoked(let transaction):
  ///     // A revocation carries the id of the purchase it revokes.
  ///     try revoke(transaction)
  ///   }
  /// }
  /// ```
  ///
  /// `handler` must not call ``refresh()``, ``start(handling:)``, or any purchase method on the
  /// store: its own delivery is at the head of the queue those wait on. From inside it, a
  /// refresh or start recomputes entitlements and returns without waiting for deliveries, and a
  /// purchase logs a fault and throws ``PurchaseError/Code/unsupported``.
  public func start(
    handling handler: @escaping @MainActor (TransactionEvent) async throws -> Void
  ) async {
    await begin(handler: handler)
  }

  private func begin(handler: Handler?) async {
    if let handler { self.handler = handler }
    guard !isStarted else {
      await refresh()
      return
    }
    isStarted = true
    // The stream is taken before the task exists, so an update is not missed between the two. The
    // task holds the store weakly and binds it per element, so a released store ends the loop.
    let updates = client.updates()
    listenerTask = Task { @MainActor [weak self] in
      for await transaction in updates {
        guard let self else { return }
        logger.info("Received update \(Self.describe(transaction), privacy: .public).")
        _ = delivery(of: transaction)
      }
    }
    await recomputeEntitlements()
    await drainUnfinished()
    _ = try? await loadProducts()
  }

  // MARK: Purchasing

  /// Purchases `product` with `options`. Returns ``PurchaseOutcome/success(_:)`` only after the
  /// handler delivered the transaction and it was finished.
  ///
  /// StoreKit can record a purchase and still end the call cancelled or failed, as it can when the
  /// app leaves the foreground while StoreKit's own confirmation is on screen. When a purchase ends
  /// that way, the store collects the transactions left unfinished and recomputes entitlements. If
  /// that delivered a purchase of `product` made since the call began, the store returns
  /// ``PurchaseOutcome/success(_:)`` with it instead; otherwise it returns or throws what StoreKit
  /// reported.
  ///
  /// - Throws: ``PurchaseError/Code/deliveryFailed`` if the handler threw, or if there is no
  ///   handler and `product` is a consumable or non-renewing subscription; the transaction stays
  ///   unfinished and is delivered again on the next ``refresh()`` or launch. Any error the
  ///   store reported is rethrown.
  @available(
    visionOS, unavailable,
    message: "Use purchase(_:confirmIn:options:) or purchase(_:using:options:) from InAppPurchaseUI"
  )
  public func purchase(
    _ product: PurchaseProduct,
    options: Set<Product.PurchaseOption> = []
  ) async throws(PurchaseError) -> PurchaseOutcome {
    try await purchase(product, options: options, purchaser: nil)
  }

  /// Purchases `product` with `options` through `purchaser`, so the confirmation sheet appears in
  /// a context the app chooses. Returns ``PurchaseOutcome/success(_:)`` only after the handler
  /// delivered the transaction and it was finished.
  ///
  /// `InAppPurchaseUI` wraps this for a scene, a view controller, a window, and SwiftUI's
  /// `@Environment(\.purchase)`. On visionOS, where ``purchase(_:options:)`` is unavailable, this
  /// is the purchase path. A store backed by `MockPurchaseClient` ignores `purchaser`.
  ///
  /// - Throws: The same errors as ``purchase(_:options:)``.
  public func purchase(
    _ product: PurchaseProduct,
    using purchaser: Purchaser,
    options: Set<Product.PurchaseOption> = []
  ) async throws(PurchaseError) -> PurchaseOutcome {
    try await purchase(product, options: options, purchaser: purchaser)
  }

  /// Purchases `product` with `options` through `purchaser`, or through the client's own path when
  /// `purchaser` is `nil`. See ``purchase(_:options:)``.
  package func purchase(
    _ product: PurchaseProduct,
    options: Set<Product.PurchaseOption>,
    purchaser: Purchaser?
  ) async throws(PurchaseError) -> PurchaseOutcome {
    guard !Self.isDelivering else {
      logger.fault(
        """
        A purchase was started from inside the transaction handler. The handler's own delivery is \
        at the head of the queue a purchase waits on, so the purchase is refused.
        """
      )
      throw PurchaseError(.unsupported)
    }
    let start = Date()
    let outcome: PurchaseOutcome
    do {
      outcome = try await client.purchase(product, options: options, purchaser: purchaser)
    } catch {
      logger.info(
        """
        StoreKit's purchase of \(product.id, privacy: .public) threw \
        \(error.code.rawValue, privacy: .public).
        """
      )
      if let recorded = try await recordedPurchase(of: product.id, since: start) {
        return .success(recorded)
      }
      throw error
    }
    logger.info(
      """
      StoreKit's purchase of \(product.id, privacy: .public) \
      \(Self.describe(outcome), privacy: .public).
      """
    )
    if case .userCancelled = outcome,
      let recorded = try await recordedPurchase(of: product.id, since: start)
    {
      return .success(recorded)
    }
    // Mutating a set in place notifies observers even when nothing changes, so check first.
    if case .pending = outcome, !pendingProductIDs.contains(product.id) {
      pendingProductIDs.insert(product.id)
    }
    guard case .success(let transaction) = outcome else { return outcome }
    guard let delivery = delivery(of: transaction) else { return outcome }
    guard await delivery.value else { throw PurchaseError(.deliveryFailed) }
    return outcome
  }

  /// Delivers a purchase of the product with `productID` that StoreKit recorded although the
  /// purchase call reported none, and returns it once finished, or `nil` if there is none.
  ///
  /// StoreKit can record a purchase and still end the call cancelled or failed, such as when the
  /// app leaves the foreground while StoreKit's own confirmation is on screen. Such a purchase does
  /// not arrive as a transaction update; it waits among the unfinished transactions. Only a
  /// transaction dated at or after `start` counts, so an earlier purchase of the same product is
  /// never taken for this one.
  ///
  /// - Throws: ``PurchaseError/Code/deliveryFailed`` if such a purchase was found but its delivery
  ///   failed.
  private func recordedPurchase(
    of productID: String,
    since start: Date
  ) async throws(PurchaseError) -> PurchaseTransaction? {
    var deliveries = await drainUnfinished()
    await recomputeEntitlements()
    // One delivered from the updates stream while the call ran is already finished, so it is no
    // longer among the unfinished transactions.
    if let finished = newestFinishedPurchases[productID] {
      deliveries.append((finished, true))
    }
    let match =
      deliveries
      .filter { delivered in
        delivered.transaction.productID == productID && delivered.transaction.revocationDate == nil
          && delivered.transaction.purchaseDate >= start
      }
      .max { $0.transaction.purchaseDate < $1.transaction.purchaseDate }
    guard let match else {
      logger.info(
        "No purchase of \(productID, privacy: .public) was recorded since the purchase began.")
      return nil
    }
    guard match.isFinished else {
      logger.info(
        """
        StoreKit recorded \(Self.describe(match.transaction), privacy: .public) during a \
        purchase it did not report, but its delivery failed.
        """
      )
      throw PurchaseError(.deliveryFailed)
    }
    logger.info(
      """
      StoreKit recorded \(Self.describe(match.transaction), privacy: .public) during a \
      purchase it did not report. It was delivered, and the purchase returns success.
      """
    )
    return match.transaction
  }

  // MARK: Refreshing

  /// Retries transactions left unfinished, recomputes ``purchasedProductIDs``, and reloads
  /// ``products`` if the last load failed or left a requested product missing. Call it when the
  /// app returns to the foreground. A product that stays missing is reloaded on every refresh.
  public func refresh() async {
    await recomputeEntitlements()
    await drainUnfinished()
    if loadError != nil || !missingProductIDs.isEmpty { _ = try? await loadProducts() }
  }

  /// Syncs with the store, which may ask the customer to sign in, then recomputes and returns
  /// ``purchasedProductIDs``. Call it only from an explicit action, such as a Restore button.
  @discardableResult
  public func restore() async throws(PurchaseError) -> Set<String> {
    try await client.sync()
    await recomputeEntitlements()
    return purchasedProductIDs
  }

  // MARK: Previewing

  /// A store that answers from fixed values, for a SwiftUI preview. It offers `products`, reports
  /// `purchasedProductIDs` as owned, and completes no purchase.
  public static func preview(
    products: [PurchaseProduct] = [],
    purchasedProductIDs: Set<String> = []
  ) -> PurchaseStore {
    let client = PreviewPurchaseClient(
      products: products,
      purchasedProductIDs: purchasedProductIDs.sorted()
    )
    let store = PurchaseStore(client: client, productIDs: products.map(\.id))
    store.products = products
    store.purchasedProductIDs = purchasedProductIDs
    return store
  }

  // MARK: Delivering

  /// Queues `transaction` for the handler and returns the task that completes once it has been
  /// finished (`true`) or its delivery failed (`false`). Returns `nil` if it was already finished
  /// in this process, and the running task if it is already queued.
  private func delivery(of transaction: PurchaseTransaction) -> Task<Bool, Never>? {
    let key = DeliveryKey(transaction)
    // The approval has arrived, so the product is no longer pending even if its delivery fails: a
    // consumable with no handler is never delivered, and would otherwise stay pending for good.
    if transaction.revocationDate == nil, pendingProductIDs.contains(transaction.productID) {
      pendingProductIDs.remove(transaction.productID)
    }
    if deliveredKeys.contains(key) { return nil }
    if let running = deliveries[key] { return running }
    let previous = queueTail
    let task = Task { @MainActor in
      _ = await previous?.value
      return await self.deliver(transaction, key: key)
    }
    deliveries[key] = task
    queueTail = task
    return task
  }

  private func deliver(_ transaction: PurchaseTransaction, key: DeliveryKey) async -> Bool {
    defer { deliveries[key] = nil }
    if let handler {
      let event: TransactionEvent =
        transaction.revocationDate == nil ? .purchased(transaction) : .revoked(transaction)
      do {
        try await Self.$isDelivering.withValue(true) { try await handler(event) }
      } catch {
        logger.error(
          """
          The handler threw for transaction \(transaction.id, privacy: .public) of \
          \(transaction.productID, privacy: .public): \(String(describing: error), privacy: .private). \
          It is left unfinished and will be delivered again.
          """
        )
        return false
      }
    } else if !Self.isOwnershipTheContent(transaction.productType) {
      logger.fault(
        """
        Transaction \(transaction.id, privacy: .public) of \
        \(transaction.productID, privacy: .public) needs a handler to deliver its content. \
        Start the store with start(handling:). It is left unfinished.
        """
      )
      return false
    }
    await client.finish(transaction)
    logger.info("Finished \(Self.describe(transaction), privacy: .public).")
    deliveredKeys.insert(key)
    if transaction.revocationDate == nil,
      transaction.purchaseDate
        >= newestFinishedPurchases[transaction.productID]?.purchaseDate ?? .distantPast
    {
      newestFinishedPurchases[transaction.productID] = transaction
    }
    await recomputeEntitlements()
    return true
  }

  /// Queues every transaction left unfinished and waits for the deliveries, except from inside the
  /// handler, whose own delivery is among them: there it only queues them and returns none.
  ///
  /// - Returns: Each transaction delivered, and whether it was finished. One already finished in
  ///   this process counts as finished.
  @discardableResult
  private func drainUnfinished() async -> [(transaction: PurchaseTransaction, isFinished: Bool)] {
    let unfinished = await client.unfinished()
    if unfinished.isEmpty { logger.info("Collected no unfinished transactions.") }
    for transaction in unfinished {
      logger.info("Collected unfinished \(Self.describe(transaction), privacy: .public).")
    }
    let queued = unfinished.map { ($0, delivery(of: $0)) }
    guard !Self.isDelivering else { return [] }
    var delivered: [(transaction: PurchaseTransaction, isFinished: Bool)] = []
    for (transaction, delivery) in queued {
      delivered.append((transaction, await delivery?.value ?? true))
    }
    return delivered
  }

  /// Whether owning a product of `type` is its whole content, so the store can finish it with no
  /// handler without losing anything.
  private static func isOwnershipTheContent(_ type: Product.ProductType) -> Bool {
    type == .nonConsumable || type == .autoRenewable
  }

  // MARK: Entitlements

  /// Reads the current entitlements and publishes them. The read runs in a task the store owns, so
  /// a caller cancelled midway cannot publish a partial set, and this returns only once the newest
  /// read in flight has been applied, so every caller returns with the latest result.
  private func recomputeEntitlements() async {
    entitlementGeneration += 1
    let generation = entitlementGeneration
    let client = client
    let task = Task { @MainActor [weak self] in
      let transactions = await client.currentEntitlements()
      guard let self else { return }
      let returned = Self.describe(transactions)
      guard generation == entitlementGeneration else {
        logger.info(
          """
          Entitlement read \(generation, privacy: .public) returned \(returned, privacy: .public). \
          It was superseded by read \(self.entitlementGeneration, privacy: .public) and not applied.
          """
        )
        return
      }
      apply(entitlements: transactions)
      logger.info(
        """
        Entitlement read \(generation, privacy: .public) returned \(returned, privacy: .public). \
        It was applied, owning \(Self.describe(self.purchasedProductIDs), privacy: .public).
        """
      )
    }
    recomputeTask = task
    var awaited = task
    await awaited.value
    while let latest = recomputeTask, latest != awaited {
      awaited = latest
      await awaited.value
    }
  }

  private func apply(entitlements transactions: [PurchaseTransaction]) {
    let current = transactions.filter { Self.isCurrent($0) }
    let ids = Set(current.map(\.productID))
    if ids != purchasedProductIDs { purchasedProductIDs = ids }
    if !pendingProductIDs.isDisjoint(with: ids) { pendingProductIDs.subtract(ids) }
    let now = Date()
    scheduleExpiry(at: current.compactMap(\.expirationDate).filter { $0 > now }.min())
  }

  /// Whether `transaction` counts as owned. A past `expirationDate` does not rule a subscription
  /// out: the store reports one only while it is current, and keeps reporting it through a billing
  /// grace period, when the paid period has ended but no renewal has been recorded yet.
  ///
  /// A consumable never counts: owning one unlocks nothing, so one the store lists while it is
  /// unfinished must not gate a feature.
  private static func isCurrent(_ transaction: PurchaseTransaction) -> Bool {
    transaction.revocationDate == nil && !transaction.isUpgraded
      && transaction.productType != .nonRenewable && transaction.productType != .consumable
  }

  /// Expiry emits nothing on the updates stream, so the store wakes itself at the earliest one
  /// still ahead. A subscription past its date is left to the store's own listing.
  private func scheduleExpiry(at date: Date?) {
    expiryTask?.cancel()
    expiryTask = nil
    guard let date else { return }
    let delay = Duration.seconds(date.timeIntervalSinceNow)
    let sleep = sleep
    expiryTask = Task { @MainActor [weak self] in
      do { try await sleep(delay) } catch { return }
      guard !Task.isCancelled, let self else { return }
      await recomputeEntitlements()
    }
  }

  // MARK: Logging

  /// Names `transaction` for the log by its identifier and product, which identify no customer.
  private static func describe(_ transaction: PurchaseTransaction) -> String {
    let kind = transaction.revocationDate == nil ? "transaction" : "revocation"
    return "\(kind) \(transaction.id) of \(transaction.productID)"
  }

  private static func describe(_ transactions: [PurchaseTransaction]) -> String {
    transactions.isEmpty ? "nothing" : transactions.map(describe).joined(separator: ", ")
  }

  private static func describe(_ productIDs: Set<String>) -> String {
    productIDs.isEmpty ? "nothing" : productIDs.sorted().joined(separator: ", ")
  }

  private static func describe(_ outcome: PurchaseOutcome) -> String {
    switch outcome {
    case .pending: "is pending approval"
    case .success(let transaction): "succeeded with \(describe(transaction))"
    case .userCancelled: "was cancelled"
    }
  }

  // MARK: Products

  /// Loads ``products``, or joins the load already running, and returns them.
  ///
  /// On success, ``products`` holds the result in identifier order, ``missingProductIDs`` the
  /// identifiers the store does not sell, and ``loadError`` is `nil`. On failure, ``loadError``
  /// holds the error, ``products`` and ``missingProductIDs`` are left as they were, and the error
  /// is thrown. ``start()`` and ``refresh()`` load this way, so call it only to retry from a
  /// button, or to load before purchasing a product that is not loaded yet.
  ///
  /// A call while a load runs awaits that load's result instead of starting another, and the load
  /// runs to completion even if the task that started it is cancelled.
  @discardableResult
  public func loadProducts() async throws(PurchaseError) -> [PurchaseProduct] {
    let load: Task<Result<[PurchaseProduct], PurchaseError>, Never>
    if let running = productLoad {
      load = running
    } else {
      isLoadingProducts = true
      let client = client
      let productIDs = productIDs
      load = Task { @MainActor [weak self] in
        let result: Result<[PurchaseProduct], PurchaseError>
        do throws(PurchaseError) {
          let loaded = try await client.products(for: productIDs)
          let byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
          result = .success(productIDs.compactMap { byID[$0] })
        } catch {
          result = .failure(error)
        }
        guard let self else { return result }
        switch result {
        case .success(let ordered):
          products = ordered
          missingProductIDs = Set(productIDs).subtracting(ordered.map(\.id))
          loadError = nil
        case .failure(let error):
          loadError = error
        }
        productLoad = nil
        isLoadingProducts = false
        return result
      }
      productLoad = load
    }
    return try await load.value.get()
  }
}

/// The subsystem every line the package logs is filed under, so Console can filter to the package.
let logSubsystem = "dev.cooperlabs.InAppPurchase"

private let logger = Logger(subsystem: logSubsystem, category: "PurchaseStore")
