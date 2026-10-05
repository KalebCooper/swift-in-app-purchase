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

  @Test func aTransactionSentWithNoStreamOpenIsDropped() async {
    let mock = MockPurchaseClient()
    mock.send(transaction(8))
    var updates = mock.updates().makeAsyncIterator()

    mock.send(transaction(9))

    #expect(await updates.next() == transaction(9))
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
