import Foundation
import InAppPurchase
import InAppPurchaseTesting
import Testing

@Suite struct MockPurchaseClientTests {
  private let small = PurchaseProduct(
    displayName: "Small tip",
    displayPrice: "$0.99",
    id: "tip.small",
    type: .consumable
  )
  private let large = PurchaseProduct(
    displayName: "Large tip",
    displayPrice: "$4.99",
    id: "tip.large",
    type: .consumable
  )
  private let pro = PurchaseProduct(
    displayName: "Pro",
    displayPrice: "$9.99",
    id: "pro.lifetime",
    type: .nonConsumable
  )

  private func transaction(_ id: UInt64, _ productID: String = "tip.small") -> PurchaseTransaction {
    PurchaseTransaction(
      id: id,
      productID: productID,
      productType: .consumable,
      purchaseDate: Date(timeIntervalSince1970: 1_800_000_000)
    )
  }

  private func tip(_ id: UInt64) -> PurchaseTransaction {
    transaction(id)
  }

  private func lifetime(_ id: UInt64) -> PurchaseTransaction {
    PurchaseTransaction(
      id: id,
      productID: "pro.lifetime",
      productType: .nonConsumable,
      purchaseDate: Date(timeIntervalSince1970: 1_800_000_000)
    )
  }

  private func monthly(_ id: UInt64) -> PurchaseTransaction {
    let purchaseDate = Date(timeIntervalSince1970: 1_800_000_000 + Double(id) * 2_592_000)
    return PurchaseTransaction(
      expirationDate: purchaseDate.addingTimeInterval(2_592_000),
      id: id,
      originalID: 1,
      productID: "pro.monthly",
      productType: .autoRenewable,
      purchaseDate: purchaseDate
    )
  }

  private func revoked(_ transaction: PurchaseTransaction) -> PurchaseTransaction {
    PurchaseTransaction(
      appAccountToken: transaction.appAccountToken,
      expirationDate: transaction.expirationDate,
      id: transaction.id,
      isUpgraded: transaction.isUpgraded,
      originalID: transaction.originalID,
      productID: transaction.productID,
      productType: transaction.productType,
      purchaseDate: transaction.purchaseDate,
      quantity: transaction.quantity,
      revocationDate: transaction.purchaseDate.addingTimeInterval(60)
    )
  }

  // MARK: Answers what is set

  @Test func aNewMockOwnsNothingSellsNothingAndReportsACancelledPurchase() async throws {
    let mock = MockPurchaseClient()

    #expect(await mock.currentEntitlements().isEmpty)
    #expect(await mock.unfinished().isEmpty)
    #expect(try await mock.products(for: ["tip.small"]).isEmpty)
    let outcome = try await mock.purchase(small, options: [], purchaser: nil)
    if case .userCancelled = outcome {} else { Issue.record("expected .userCancelled") }
    try await mock.sync()
    #expect(mock.finishedTransactions.isEmpty)
  }

  @Test func returnsTheEntitlementsItWasGiven() async {
    let mock = MockPurchaseClient()
    mock.entitlements = [transaction(1), transaction(2)]

    #expect(await mock.currentEntitlements() == [transaction(1), transaction(2)])
  }

  @Test func returnsTheUnfinishedTransactionsItWasGiven() async {
    let mock = MockPurchaseClient()
    mock.unfinishedTransactions = [transaction(3)]

    #expect(await mock.unfinished() == [transaction(3)])
  }

  @Test func returnsOnlyTheRequestedProductsInTheOrderTheyWereSet() async throws {
    let mock = MockPurchaseClient()
    mock.products = [small, large, pro]

    let products = try await mock.products(for: ["pro.lifetime", "tip.small", "tip.missing"])

    #expect(products == [small, pro])
  }

  @Test func throwsTheProductsErrorItWasGiven() async {
    let mock = MockPurchaseClient()
    mock.products = [small]
    mock.productsError = PurchaseError(.networkUnavailable)

    do {
      _ = try await mock.products(for: ["tip.small"])
      Issue.record("products(for:) did not throw")
    } catch {
      #expect(error.code == .networkUnavailable)
    }
  }

  @Test func purchaseReturnsTheOutcomeItWasGiven() async throws {
    let mock = MockPurchaseClient()
    mock.purchaseResult = .success(.success(transaction(4)))

    let outcome = try await mock.purchase(small, options: [], purchaser: nil)

    guard case .success(let purchased) = outcome else {
      Issue.record("expected .success")
      return
    }
    #expect(purchased == transaction(4))
  }

  @Test func purchaseThrowsTheErrorItWasGiven() async {
    let mock = MockPurchaseClient()
    mock.purchaseResult = .failure(PurchaseError(.unverified))

    do {
      _ = try await mock.purchase(small, options: [], purchaser: nil)
      Issue.record("purchase(_:options:purchaser:) did not throw")
    } catch {
      #expect(error.code == .unverified)
    }
  }

  @Test func syncThrowsTheErrorItWasGiven() async {
    let mock = MockPurchaseClient()
    mock.syncResult = .failure(PurchaseError(.userCancelled))

    do {
      try await mock.sync()
      Issue.record("sync() did not throw")
    } catch {
      #expect(error.code == .userCancelled)
    }
  }

  // MARK: Updates

  @Test func aSentTransactionReachesEveryUpdatesStream() async {
    let mock = MockPurchaseClient()
    let first = mock.updates()
    let second = mock.updates()

    mock.send(transaction(5))

    var firstIterator = first.makeAsyncIterator()
    var secondIterator = second.makeAsyncIterator()
    #expect(await firstIterator.next() == transaction(5))
    #expect(await secondIterator.next() == transaction(5))
  }

  @Test func sentTransactionsArriveInTheOrderTheyWereSent() async {
    let mock = MockPurchaseClient()
    var updates = mock.updates().makeAsyncIterator()

    mock.send(transaction(6))
    mock.send(transaction(7))

    #expect(await updates.next() == transaction(6))
    #expect(await updates.next() == transaction(7))
  }

  @Test func aTransactionSentWithNoStreamOpenReachesNoStreamButStaysUnfinished() async {
    let mock = MockPurchaseClient()
    mock.send(transaction(8))
    var updates = mock.updates().makeAsyncIterator()

    mock.send(transaction(9))

    #expect(await updates.next() == transaction(9))
    #expect(await mock.unfinished() == [transaction(8), transaction(9)])
  }

  @Test func countsTheUpdatesStreamsStillOpen() {
    let mock = MockPurchaseClient()
    #expect(mock.activeUpdateSubscriptions == 0)

    let kept = mock.updates()
    do {
      let released = mock.updates()
      #expect(mock.activeUpdateSubscriptions == 2)
      _ = released
    }

    #expect(mock.activeUpdateSubscriptions == 1)
    _ = kept
  }

  // MARK: Ledger

  @Test func aSuccessfulPurchaseOfANonConsumableJoinsTheEntitlements() async throws {
    let mock = MockPurchaseClient()
    mock.purchaseResult = .success(.success(lifetime(1)))

    _ = try await mock.purchase(pro, options: [], purchaser: nil)

    #expect(await mock.currentEntitlements() == [lifetime(1)])
    #expect(await mock.unfinished() == [lifetime(1)])
  }

  @Test func aSuccessfulPurchaseOfAConsumableDoesNotJoinTheEntitlements() async throws {
    let mock = MockPurchaseClient()
    mock.purchaseResult = .success(.success(tip(1)))

    _ = try await mock.purchase(small, options: [], purchaser: nil)

    #expect(await mock.currentEntitlements().isEmpty)
    #expect(await mock.unfinished() == [tip(1)])
  }

  @Test func aSentRenewalReplacesTheEntitlementForItsProduct() async {
    let mock = MockPurchaseClient()
    mock.entitlements = [lifetime(1), monthly(1)]

    mock.send(monthly(2))

    #expect(await mock.currentEntitlements() == [lifetime(1), monthly(2)])
  }

  @Test func aSentRevocationRemovesTheEntitlementWithItsID() async {
    let mock = MockPurchaseClient()
    mock.entitlements = [lifetime(1)]

    mock.send(revoked(lifetime(1)))

    #expect(await mock.currentEntitlements().isEmpty)
    #expect(await mock.unfinished() == [revoked(lifetime(1))])
  }

  @Test func aSentTransactionIsUnfinishedUntilFinished() async {
    let mock = MockPurchaseClient()

    mock.send(tip(1))
    mock.send(tip(1))
    #expect(await mock.unfinished() == [tip(1)])

    await mock.finish(tip(1))
    #expect(await mock.unfinished().isEmpty)
  }

  // MARK: Purchases

  @Test func aPerProductResultOverridesTheDefault() async throws {
    let mock = MockPurchaseClient()
    mock.purchaseResults["pro.lifetime"] = .success(.pending)

    let overridden = try await mock.purchase(pro, options: [], purchaser: nil)
    let defaulted = try await mock.purchase(small, options: [], purchaser: nil)

    if case .pending = overridden {} else { Issue.record("expected .pending") }
    if case .userCancelled = defaulted {} else { Issue.record("expected .userCancelled") }
  }

  @Test func recordsEachPurchaseRequest() async throws {
    let mock = MockPurchaseClient()
    #expect(mock.purchaseRequests.isEmpty)

    _ = try await mock.purchase(pro, options: [], purchaser: nil)
    _ = try await mock.purchase(large, options: [.quantity(2)], purchaser: nil)

    #expect(mock.purchaseRequests.map(\.product) == [pro, large])
    #expect(mock.purchaseRequests.map(\.options) == [[], [.quantity(2)]])
    #expect(mock.purchaseRequests.map(\.usesPurchaser) == [false, false])
  }

  // MARK: Finishes

  @Test func recordsFinishedTransactionsInCallOrder() async {
    let mock = MockPurchaseClient()

    await mock.finish(transaction(10))
    await mock.finish(transaction(11))

    #expect(mock.finishedTransactions == [transaction(10), transaction(11)])
  }

  @Test func aFinishedTransactionIsNoLongerUnfinished() async {
    let mock = MockPurchaseClient()
    mock.unfinishedTransactions = [transaction(12), transaction(13)]

    await mock.finish(transaction(12))

    #expect(await mock.unfinished() == [transaction(13)])
  }

  @Test func theNextFinishCanHaveHappenedAlready() async throws {
    let mock = MockPurchaseClient()
    await mock.finish(transaction(14))

    #expect(try await mock.nextFinishedTransaction() == transaction(14))
  }

  @Test func waitingForTheNextFinishResumesWhenItHappens() async throws {
    let mock = MockPurchaseClient()
    let waiter = Task { try await mock.nextFinishedTransaction() }

    await mock.finish(transaction(15))

    #expect(try await waiter.value == transaction(15))
  }

  @Test func eachFinishIsReturnedOnceInOrder() async throws {
    let mock = MockPurchaseClient()
    await mock.finish(transaction(16))
    await mock.finish(transaction(17))

    #expect(try await mock.nextFinishedTransaction() == transaction(16))
    #expect(try await mock.nextFinishedTransaction() == transaction(17))
    #expect(mock.finishedTransactions == [transaction(16), transaction(17)])
  }

  @Test func cancellingAWaitForTheNextFinishThrows() async {
    let mock = MockPurchaseClient()
    let waiter = Task { try await mock.nextFinishedTransaction() }

    waiter.cancel()

    await #expect(throws: CancellationError.self) { try await waiter.value }
  }
}
