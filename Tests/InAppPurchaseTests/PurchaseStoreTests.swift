import Foundation
import InAppPurchase
import InAppPurchaseTesting
import Observation
import StoreKit
import Synchronization
import Testing

/// Records whether an observation's change handler ran.
private final class ChangeFlag: Sendable {
  private let value = Mutex(false)

  /// Whether ``set()`` has been called.
  var isSet: Bool { value.withLock { $0 } }

  func set() {
    value.withLock { $0 = true }
  }
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct PurchaseStoreTests {
  private let purchaseDate = Date(timeIntervalSince1970: 1_800_000_000)

  private let small = PurchaseProduct(
    displayName: "Small tip",
    displayPrice: "$0.99",
    id: "tip.small",
    type: .consumable
  )
  private let pro = PurchaseProduct(
    displayName: "Pro",
    displayPrice: "$9.99",
    id: "pro.lifetime",
    type: .nonConsumable
  )

  private func tip(_ id: UInt64) -> PurchaseTransaction {
    PurchaseTransaction(
      id: id, productID: "tip.small", productType: .consumable, purchaseDate: purchaseDate)
  }

  private func lifetime(_ id: UInt64) -> PurchaseTransaction {
    PurchaseTransaction(
      id: id, productID: "pro.lifetime", productType: .nonConsumable, purchaseDate: purchaseDate)
  }

  private func makeStore(
    _ mock: MockPurchaseClient,
    productIDs: [String] = ["tip.small", "pro.lifetime"]
  ) -> PurchaseStore {
    PurchaseStore(client: mock, productIDs: productIDs)
  }

  // MARK: Start

  @Test func aNewStoreOwnsNothingAndOffersNothing() {
    let store = makeStore(MockPurchaseClient())

    #expect(store.isLoadingProducts == false)
    #expect(store.loadError == nil)
    #expect(store.missingProductIDs.isEmpty)
    #expect(store.products.isEmpty)
    #expect(store.purchasedProductIDs.isEmpty)
  }

  @Test func startingTwiceOpensOneUpdatesStream() async {
    let mock = MockPurchaseClient()
    let store = makeStore(mock)

    await store.start()
    await store.start()

    #expect(mock.activeUpdateSubscriptions == 1)
  }

  @Test func startDeliversUnfinishedTransactionsAsPurchasedThenFinishesThem() async {
    let mock = MockPurchaseClient()
    mock.unfinishedTransactions = [tip(1)]
    let recorder = HandlerRecorder(mock: mock)
    let store = makeStore(mock)

    await store.start(handling: recorder.handle)

    #expect(recorder.events.map(\.purchased) == [tip(1)])
    #expect(recorder.finishedAtInvocation == [[]])
    #expect(mock.finishedTransactions == [tip(1)])
  }

  @Test func aThrowingHandlerLeavesTheTransactionUnfinishedUntilRefreshRetriesIt() async {
    let mock = MockPurchaseClient()
    mock.unfinishedTransactions = [tip(1)]
    let recorder = HandlerRecorder(mock: mock)
    recorder.error = HandlerFailure()
    let store = makeStore(mock)

    await store.start(handling: recorder.handle)
    #expect(mock.finishedTransactions.isEmpty)
    #expect(await mock.unfinished() == [tip(1)])

    recorder.error = nil
    await store.refresh()

    #expect(recorder.events.map(\.purchased) == [tip(1), tip(1)])
    #expect(mock.finishedTransactions == [tip(1)])
  }

  @Test func aTransactionFromUnfinishedAndUpdatesReachesTheHandlerOnce() async throws {
    let mock = MockPurchaseClient()
    mock.unfinishedTransactions = [tip(1)]
    let recorder = HandlerRecorder(mock: mock)
    let store = makeStore(mock)
    await store.start(handling: recorder.handle)

    mock.send(tip(1))
    mock.send(tip(2))

    #expect(try await mock.nextFinishedTransaction() == tip(1))
    #expect(try await mock.nextFinishedTransaction() == tip(2))
    #expect(recorder.events.map(\.purchased) == [tip(1), tip(2)])
  }

  @Test func anUpdateForATransactionStillInTheHandlerIsMergedIntoThatDelivery() async throws {
    let mock = MockPurchaseClient()
    mock.unfinishedTransactions = [tip(1)]
    let recorder = HandlerRecorder(mock: mock)
    let gate = Gate()
    recorder.gateForFirstInvocation = gate
    let store = makeStore(mock)
    var starts = recorder.starts.makeAsyncIterator()

    let started = Task { await store.start(handling: recorder.handle) }
    _ = await starts.next()
    mock.send(tip(1))
    mock.send(tip(2))
    for _ in 0..<10 { await Task.yield() }
    gate.open()
    await started.value

    #expect(try await mock.nextFinishedTransaction() == tip(1))
    #expect(try await mock.nextFinishedTransaction() == tip(2))
    #expect(recorder.events.map(\.purchased) == [tip(1), tip(2)])
  }

  @Test func startComputesEntitlementsBeforeTheHandlerDeliversUnfinishedTransactions() async {
    let mock = MockPurchaseClient()
    mock.entitlements = [lifetime(1)]
    mock.unfinishedTransactions = [tip(2)]
    let recorder = HandlerRecorder(mock: mock)
    let gate = Gate()
    recorder.gateForFirstInvocation = gate
    let store = makeStore(mock)
    var starts = recorder.starts.makeAsyncIterator()

    let started = Task { await store.start(handling: recorder.handle) }
    _ = await starts.next()

    #expect(store.purchasedProductIDs == ["pro.lifetime"])

    gate.open()
    await started.value
  }

  @Test func aHandlerThatRefreshesTheStoreReturnsAndTheQueueKeepsMoving() async throws {
    let mock = MockPurchaseClient()
    mock.unfinishedTransactions = [tip(1)]
    let recorder = HandlerRecorder(mock: mock)
    let store = makeStore(mock)
    recorder.actionForFirstInvocation = { await store.refresh() }

    await store.start(handling: recorder.handle)
    #expect(recorder.events.map(\.purchased) == [tip(1)])
    #expect(mock.finishedTransactions == [tip(1)])

    mock.send(tip(2))

    #expect(try await mock.nextFinishedTransaction() == tip(1))
    #expect(try await mock.nextFinishedTransaction() == tip(2))
  }

  @Test func eventsArrivingTogetherRunTheHandlerOneAfterTheOther() async throws {
    let mock = MockPurchaseClient()
    let recorder = HandlerRecorder(mock: mock)
    let gate = Gate()
    recorder.gateForFirstInvocation = gate
    let store = makeStore(mock)
    await store.start(handling: recorder.handle)
    var starts = recorder.starts.makeAsyncIterator()

    mock.send(tip(1))
    _ = await starts.next()
    mock.send(tip(2))
    for _ in 0..<10 { await Task.yield() }

    #expect(recorder.events.map(\.purchased) == [tip(1)])
    #expect(mock.finishedTransactions.isEmpty)

    gate.open()

    #expect(try await mock.nextFinishedTransaction() == tip(1))
    #expect(try await mock.nextFinishedTransaction() == tip(2))
    #expect(recorder.finishedAtInvocation == [[], [tip(1)]])
    #expect(recorder.maxActive == 1)
  }

  @Test func aRevocationReachesTheHandlerAsRevokedAndDropsTheEntitlement() async throws {
    let mock = MockPurchaseClient()
    mock.entitlements = [lifetime(1)]
    mock.unfinishedTransactions = [lifetime(1)]
    let recorder = HandlerRecorder(mock: mock)
    let store = makeStore(mock)
    await store.start(handling: recorder.handle)
    #expect(store.purchasedProductIDs == ["pro.lifetime"])
    #expect(recorder.events.map(\.purchased) == [lifetime(1)])
    let revocation = PurchaseTransaction(
      id: 1,
      productID: "pro.lifetime",
      productType: .nonConsumable,
      purchaseDate: purchaseDate,
      revocationDate: purchaseDate.addingTimeInterval(60)
    )

    mock.entitlements = []
    mock.send(revocation)

    #expect(try await mock.nextFinishedTransaction() == lifetime(1))
    #expect(try await mock.nextFinishedTransaction() == revocation)
    #expect(recorder.events.map(\.purchased) == [lifetime(1), nil])
    #expect(recorder.events.map(\.revoked) == [nil, revocation])
    for await ids in Observations({ @MainActor in store.purchasedProductIDs }) {
      if ids.isEmpty { break }
    }
    #expect(store.purchasedProductIDs.isEmpty)
  }

  @Test func startWithNoHandlerFinishesANonConsumableAndLeavesAConsumableUnfinished() async {
    let mock = MockPurchaseClient()
    mock.unfinishedTransactions = [lifetime(1), tip(2)]
    let store = makeStore(mock)

    await store.start()

    #expect(mock.finishedTransactions == [lifetime(1)])
    #expect(await mock.unfinished() == [tip(2)])
  }

  @Test func startingAgainWithAHandlerDeliversTheConsumablesThatWereHeld() async {
    let mock = MockPurchaseClient()
    mock.unfinishedTransactions = [tip(1)]
    let recorder = HandlerRecorder(mock: mock)
    let store = makeStore(mock)
    await store.start()

    await store.start(handling: recorder.handle)

    #expect(recorder.events.map(\.purchased) == [tip(1)])
    #expect(mock.finishedTransactions == [tip(1)])
    #expect(mock.activeUpdateSubscriptions == 1)
  }

  @Test func theListenerStopsWhenTheStoreIsReleased() async throws {
    let mock = MockPurchaseClient()
    let recorder = HandlerRecorder(mock: mock)

    do {
      mock.unfinishedTransactions = [tip(1)]
      let store = makeStore(mock)
      await store.start(handling: recorder.handle)
      #expect(mock.finishedTransactions == [tip(1)])
      #expect(mock.activeUpdateSubscriptions == 1)
    }

    #expect(mock.activeUpdateSubscriptions == 0)
  }

  // MARK: Purchase

  @Test func aSuccessfulPurchaseReturnsAfterTheHandlerRanAndTheTransactionFinished() async throws {
    let mock = MockPurchaseClient()
    mock.purchaseResult = .success(.success(lifetime(1)))
    let recorder = HandlerRecorder(mock: mock)
    let store = makeStore(mock)
    await store.start(handling: recorder.handle)

    let outcome = try await store.purchase(pro)

    guard case .success(let purchased) = outcome else {
      Issue.record("expected .success")
      return
    }
    #expect(purchased == lifetime(1))
    #expect(recorder.events.map(\.purchased) == [lifetime(1)])
    #expect(mock.finishedTransactions == [lifetime(1)])
  }

  @Test func aPurchaseWaitsForAnUpdateAlreadyInTheHandler() async throws {
    let mock = MockPurchaseClient()
    mock.purchaseResult = .success(.success(lifetime(2)))
    let recorder = HandlerRecorder(mock: mock)
    let gate = Gate()
    recorder.gateForFirstInvocation = gate
    let store = makeStore(mock)
    await store.start(handling: recorder.handle)
    var starts = recorder.starts.makeAsyncIterator()

    mock.send(tip(1))
    _ = await starts.next()
    let product = pro
    let purchase = Task { try await store.purchase(product) }
    for _ in 0..<10 { await Task.yield() }
    #expect(recorder.events.map(\.purchased) == [tip(1)])

    gate.open()
    _ = try await purchase.value

    #expect(recorder.events.map(\.purchased) == [tip(1), lifetime(2)])
    #expect(recorder.finishedAtInvocation == [[], [tip(1)]])
    #expect(recorder.maxActive == 1)
  }

  @Test func aPurchaseMergedIntoAnInFlightDeliverySharesItsResult() async {
    let mock = MockPurchaseClient()
    mock.purchaseResult = .success(.success(lifetime(1)))
    let recorder = HandlerRecorder(mock: mock)
    let gate = Gate()
    recorder.gateForFirstInvocation = gate
    let store = makeStore(mock)
    await store.start(handling: recorder.handle)
    var starts = recorder.starts.makeAsyncIterator()

    mock.send(lifetime(1))
    _ = await starts.next()
    let product = pro
    let purchase = Task { try await store.purchase(product) }
    for _ in 0..<10 { await Task.yield() }
    recorder.error = HandlerFailure()
    gate.open()

    do {
      _ = try await purchase.value
      Issue.record("purchase(_:) did not throw")
    } catch {
      #expect((error as? PurchaseError)?.code == .deliveryFailed)
    }
    #expect(recorder.events.map(\.purchased) == [lifetime(1)])
    #expect(mock.finishedTransactions.isEmpty)
  }

  @Test func aPurchaseWhoseHandlerThrowsFailsWithDeliveryFailedAndStaysUnfinished() async {
    let mock = MockPurchaseClient()
    mock.purchaseResult = .success(.success(tip(1)))
    let recorder = HandlerRecorder(mock: mock)
    recorder.error = HandlerFailure()
    let store = makeStore(mock)
    await store.start(handling: recorder.handle)

    do {
      _ = try await store.purchase(small)
      Issue.record("purchase(_:) did not throw")
    } catch {
      #expect(error.code == .deliveryFailed)
    }
    #expect(recorder.events.map(\.purchased) == [tip(1)])
    #expect(mock.finishedTransactions.isEmpty)
  }

  @Test func aPurchaseOfAConsumableWithNoHandlerFailsWithDeliveryFailed() async {
    let mock = MockPurchaseClient()
    mock.purchaseResult = .success(.success(tip(1)))
    let store = makeStore(mock)
    await store.start()

    do {
      _ = try await store.purchase(small)
      Issue.record("purchase(_:) did not throw")
    } catch {
      #expect(error.code == .deliveryFailed)
    }
    #expect(mock.finishedTransactions.isEmpty)
  }

  @Test func aPendingPurchaseReturnsAtOnceAndItsApprovalReachesTheHandler() async throws {
    let mock = MockPurchaseClient()
    mock.purchaseResult = .success(.pending)
    let recorder = HandlerRecorder(mock: mock)
    let store = makeStore(mock)
    await store.start(handling: recorder.handle)
    #expect(store.pendingProductIDs.isEmpty)

    let outcome = try await store.purchase(pro)
    if case .pending = outcome {} else { Issue.record("expected .pending") }
    #expect(recorder.events.isEmpty)
    #expect(store.pendingProductIDs == ["pro.lifetime"])

    mock.send(lifetime(1))

    #expect(try await mock.nextFinishedTransaction() == lifetime(1))
    #expect(recorder.events.map(\.purchased) == [lifetime(1)])
    #expect(store.pendingProductIDs.isEmpty)
  }

  // MARK: Pending

  @Test func aPendingPurchaseJoinsThePendingProducts() async throws {
    let mock = MockPurchaseClient()
    mock.purchaseResults["pro.lifetime"] = .success(.pending)
    let store = makeStore(mock)
    await store.start()

    _ = try await store.purchase(pro)

    #expect(store.pendingProductIDs == ["pro.lifetime"])
  }

  @Test func anApprovalLeavesThePendingProducts() async throws {
    let mock = MockPurchaseClient()
    mock.purchaseResults["pro.lifetime"] = .success(.pending)
    let store = makeStore(mock)
    await store.start()
    _ = try await store.purchase(pro)

    mock.send(lifetime(1))

    #expect(try await mock.nextFinishedTransaction() == lifetime(1))
    #expect(store.pendingProductIDs.isEmpty)
  }

  @Test func anApprovedConsumableWithNoHandlerLeavesThePendingProducts() async throws {
    let mock = MockPurchaseClient()
    mock.purchaseResults["tip.small"] = .success(.pending)
    let store = makeStore(mock)
    await store.start()
    _ = try await store.purchase(small)
    #expect(store.pendingProductIDs == ["tip.small"])

    mock.send(tip(1))
    await store.refresh()

    #expect(store.pendingProductIDs.isEmpty)
    #expect(mock.finishedTransactions.isEmpty)
  }

  @Test func anOwnedProductLeavesThePendingProductsOnRefresh() async throws {
    let mock = MockPurchaseClient()
    mock.purchaseResults["pro.lifetime"] = .success(.pending)
    let store = makeStore(mock)
    await store.start()
    _ = try await store.purchase(pro)

    mock.entitlements = [lifetime(1)]
    await store.refresh()

    #expect(store.pendingProductIDs.isEmpty)
  }

  @Test func aRevocationDoesNotTouchThePendingProducts() async throws {
    let mock = MockPurchaseClient()
    mock.purchaseResults["pro.lifetime"] = .success(.pending)
    let store = makeStore(mock)
    await store.start()
    _ = try await store.purchase(pro)
    let revocation = PurchaseTransaction(
      id: 9,
      productID: "pro.lifetime",
      productType: .nonConsumable,
      purchaseDate: purchaseDate,
      revocationDate: purchaseDate.addingTimeInterval(60)
    )

    mock.send(revocation)

    #expect(try await mock.nextFinishedTransaction() == revocation)
    #expect(store.pendingProductIDs == ["pro.lifetime"])
  }

  @Test func aDeliveryForAProductNotPendingDoesNotNotifyPendingObservers() async throws {
    let mock = MockPurchaseClient()
    mock.purchaseResults["tip.small"] = .success(.pending)
    let store = makeStore(mock)
    await store.start()
    _ = try await store.purchase(small)
    let changed = ChangeFlag()
    withObservationTracking {
      _ = store.pendingProductIDs
    } onChange: {
      changed.set()
    }

    mock.send(lifetime(1))
    #expect(try await mock.nextFinishedTransaction() == lifetime(1))
    // The delivery's entitlement read, which subtracts owned products, has run once this returns.
    await store.refresh()

    #expect(store.purchasedProductIDs == ["pro.lifetime"])
    #expect(store.pendingProductIDs == ["tip.small"])
    #expect(changed.isSet == false)
  }

  @Test func aCancelledPurchasePassesThrough() async throws {
    let mock = MockPurchaseClient()
    let recorder = HandlerRecorder(mock: mock)
    let store = makeStore(mock)
    await store.start(handling: recorder.handle)

    let outcome = try await store.purchase(pro)

    if case .userCancelled = outcome {} else { Issue.record("expected .userCancelled") }
    #expect(recorder.events.isEmpty)
  }

  @Test func aPurchaseErrorPassesThrough() async {
    let mock = MockPurchaseClient()
    mock.purchaseResult = .failure(PurchaseError(.unverified))
    let store = makeStore(mock)
    await store.start()

    do {
      _ = try await store.purchase(pro)
      Issue.record("purchase(_:) did not throw")
    } catch {
      #expect(error.code == .unverified)
    }
  }

  @Test func aPurchaseThroughAPurchaserHandsItToTheClient() async throws {
    let mock = MockPurchaseClient()
    let store = makeStore(mock)
    await store.start()

    _ = try await store.purchase(pro, using: Purchaser { _, _ in .userCancelled })

    #expect(mock.purchaseRequests.last?.usesPurchaser == true)
  }

  @Test func aPlainPurchaseHandsTheClientNoPurchaser() async throws {
    let mock = MockPurchaseClient()
    let store = makeStore(mock)
    await store.start()

    _ = try await store.purchase(pro)

    #expect(mock.purchaseRequests.last?.usesPurchaser == false)
  }

  @Test func aSuccessfulPurchaseThroughAPurchaserReturnsAfterDelivery() async throws {
    let mock = MockPurchaseClient()
    mock.purchaseResult = .success(.success(lifetime(1)))
    let recorder = HandlerRecorder(mock: mock)
    let store = makeStore(mock)
    await store.start(handling: recorder.handle)

    let outcome = try await store.purchase(pro, using: Purchaser { _, _ in .userCancelled })

    guard case .success(let purchased) = outcome else {
      Issue.record("expected .success")
      return
    }
    #expect(purchased == lifetime(1))
    #expect(recorder.events.map(\.purchased) == [lifetime(1)])
    #expect(mock.finishedTransactions == [lifetime(1)])
  }

  // MARK: Entitlements

  private var monthly: PurchaseTransaction {
    PurchaseTransaction(
      expirationDate: Date.distantFuture,
      id: 20,
      productID: "pro.monthly",
      productType: .autoRenewable,
      purchaseDate: purchaseDate
    )
  }

  private var revokedLifetime: PurchaseTransaction {
    PurchaseTransaction(
      id: 21,
      productID: "pro.lifetime",
      productType: .nonConsumable,
      purchaseDate: purchaseDate,
      revocationDate: purchaseDate.addingTimeInterval(60)
    )
  }

  private var upgradedMonthly: PurchaseTransaction {
    PurchaseTransaction(
      expirationDate: Date.distantFuture,
      id: 22,
      isUpgraded: true,
      productID: "pro.monthly",
      productType: .autoRenewable,
      purchaseDate: purchaseDate
    )
  }

  private var season: PurchaseTransaction {
    PurchaseTransaction(
      expirationDate: Date.distantFuture,
      id: 23,
      productID: "pro.season",
      productType: .nonRenewable,
      purchaseDate: purchaseDate
    )
  }

  /// A subscription StoreKit still lists although its paid period ended, as during a billing grace
  /// period.
  private var monthlyInGrace: PurchaseTransaction {
    PurchaseTransaction(
      expirationDate: Date(timeIntervalSinceNow: -60),
      id: 24,
      productID: "pro.monthly",
      productType: .autoRenewable,
      purchaseDate: purchaseDate
    )
  }

  private var monthlySoon: PurchaseTransaction {
    PurchaseTransaction(
      expirationDate: Date(timeIntervalSinceNow: 3_600),
      id: 20,
      productID: "pro.monthly",
      productType: .autoRenewable
    )
  }

  private var yearly: PurchaseTransaction {
    PurchaseTransaction(
      expirationDate: Date(timeIntervalSinceNow: 7_200),
      id: 26,
      productID: "pro.yearly",
      productType: .autoRenewable
    )
  }

  private func makeTimedStore(_ mock: MockPurchaseClient, sleep: ControlledSleep) -> PurchaseStore {
    PurchaseStore(
      client: mock, productIDs: ["pro.monthly", "pro.yearly"], sleep: sleep.sleep(for:))
  }

  @Test func currentPurchasesAndSubscriptionsCountAsPurchased() async {
    let mock = MockPurchaseClient()
    let live = PurchaseTransaction(
      expirationDate: Date.distantFuture,
      id: 25,
      productID: "pro.monthly",
      productType: .autoRenewable,
      purchaseDate: purchaseDate
    )
    mock.entitlements = [lifetime(1), live]
    let store = makeStore(mock)

    await store.start()

    #expect(store.purchasedProductIDs == ["pro.lifetime", "pro.monthly"])
  }

  @Test(arguments: ["revoked", "upgraded", "non-renewing"])
  func excludesFromPurchased(_ kind: String) async {
    let mock = MockPurchaseClient()
    switch kind {
    case "revoked": mock.entitlements = [revokedLifetime]
    case "upgraded": mock.entitlements = [upgradedMonthly]
    default: mock.entitlements = [season]
    }
    let store = makeStore(mock)

    await store.start()

    #expect(store.purchasedProductIDs.isEmpty)
  }

  @Test func aSubscriptionTheStoreNoLongerListsIsNotPurchased() async {
    let mock = MockPurchaseClient()
    mock.entitlements = [monthly]
    let store = makeStore(mock, productIDs: ["pro.monthly"])
    await store.start()
    #expect(store.purchasedProductIDs == ["pro.monthly"])

    mock.entitlements = []
    await store.refresh()

    #expect(store.purchasedProductIDs.isEmpty)
  }

  @Test func aListedSubscriptionPastItsExpirationStaysPurchasedAndSchedulesNoTimer() async {
    let mock = MockPurchaseClient()
    mock.entitlements = [monthlyInGrace]
    let sleep = ControlledSleep()
    let store = makeTimedStore(mock, sleep: sleep)

    await store.start()

    #expect(store.purchasedProductIDs == ["pro.monthly"])
    #expect(sleep.requestCount == 0)
  }

  @Test func isEntitledWhenAnyOfTheEntitlementsProductsIsPurchased() async {
    let mock = MockPurchaseClient()
    mock.entitlements = [lifetime(1)]
    let store = makeStore(mock)
    await store.start()

    #expect(store.isEntitled(to: Entitlement(["pro.monthly", "pro.lifetime"])))
  }

  @Test func isNotEntitledWhenNoneOfTheEntitlementsProductsIsPurchased() async {
    let mock = MockPurchaseClient()
    mock.entitlements = [lifetime(1)]
    let store = makeStore(mock)
    await store.start()

    #expect(store.isEntitled(to: Entitlement(["pro.monthly", "pro.yearly"])) == false)
  }

  @Test func theExpiryTimerRecomputesAtTheEarliestExpiration() async {
    let mock = MockPurchaseClient()
    let yearly = yearly
    mock.entitlements = [monthlySoon, yearly]
    let sleep = ControlledSleep()
    let store = makeTimedStore(mock, sleep: sleep)
    await store.start()
    #expect(store.purchasedProductIDs == ["pro.monthly", "pro.yearly"])

    let requested = await sleep.nextRequest()
    #expect(requested > .seconds(3_500) && requested <= .seconds(3_600))

    mock.entitlements = [yearly]
    sleep.wake()
    for await ids in Observations({ @MainActor in store.purchasedProductIDs }) {
      if ids == ["pro.yearly"] { break }
    }

    #expect(store.purchasedProductIDs == ["pro.yearly"])
  }

  @Test func anEarlierExpirationReplacesThePendingTimer() async {
    let mock = MockPurchaseClient()
    mock.entitlements = [yearly]
    let sleep = ControlledSleep()
    let store = makeTimedStore(mock, sleep: sleep)
    await store.start()
    let first = await sleep.nextRequest()
    #expect(first > .seconds(7_100) && first <= .seconds(7_200))

    mock.entitlements = [monthlySoon, yearly]
    await store.refresh()

    #expect(sleep.cancelledSleepCount == 1)
    let second = await sleep.nextRequest()
    #expect(second > .seconds(3_500) && second <= .seconds(3_600))
  }

  @Test func losingEverySubscriptionCancelsThePendingTimer() async {
    let mock = MockPurchaseClient()
    mock.entitlements = [yearly]
    let sleep = ControlledSleep()
    let store = makeTimedStore(mock, sleep: sleep)
    await store.start()
    _ = await sleep.nextRequest()

    mock.entitlements = []
    await store.refresh()

    #expect(store.purchasedProductIDs.isEmpty)
    #expect(sleep.cancelledSleepCount == 1)
    #expect(sleep.requestCount == 1)
  }

  @Test func anOlderRecomputeThatFinishesLateDoesNotOverwriteANewerOne() async {
    let mock = MockPurchaseClient()
    mock.entitlements = [lifetime(1)]
    let client = GatedEntitlementsClient(mock: mock, gatedCalls: [2])
    let store = PurchaseStore(client: client, productIDs: ["pro.lifetime", "pro.monthly"])
    await store.start()
    #expect(store.purchasedProductIDs == ["pro.lifetime"])

    mock.entitlements = []
    let older = Task { await store.refresh() }
    await client.gate(forCall: 2).arrival()
    mock.entitlements = [monthly]
    await store.refresh()
    #expect(store.purchasedProductIDs == ["pro.monthly"])

    client.gate(forCall: 2).open()
    await older.value

    #expect(store.purchasedProductIDs == ["pro.monthly"])
  }

  @Test func restoreReturnsTheNewestEntitlementsWhenANewerRecomputeIsInFlight() async throws {
    let mock = MockPurchaseClient()
    mock.entitlements = [lifetime(1)]
    let client = GatedEntitlementsClient(mock: mock, gatedCalls: [2, 3])
    let store = PurchaseStore(client: client, productIDs: ["pro.lifetime", "pro.monthly"])
    await store.start()

    mock.entitlements = []
    let older = Task { try await store.restore() }
    await client.gate(forCall: 2).arrival()
    mock.entitlements = [monthly]
    let newer = Task { await store.refresh() }
    await client.gate(forCall: 3).arrival()

    client.gate(forCall: 2).open()
    for _ in 0..<10 { await Task.yield() }
    client.gate(forCall: 3).open()
    await newer.value
    let restored = try await older.value

    #expect(restored == ["pro.monthly"])
    #expect(store.purchasedProductIDs == ["pro.monthly"])
  }

  // MARK: Products

  @Test func productsKeepTheRequestedOrder() async {
    let mock = MockPurchaseClient()
    mock.products = [small, pro]
    let store = makeStore(mock, productIDs: ["pro.lifetime", "tip.small"])

    await store.start()

    #expect(store.products == [pro, small])
    #expect(store.product(id: "tip.small") == small)
  }

  @Test func reportsTheRequestedProductsTheStoreDoesNotSell() async {
    let mock = MockPurchaseClient()
    mock.products = [small]
    let store = makeStore(mock, productIDs: ["tip.small", "tip.missing"])

    await store.start()

    #expect(store.products == [small])
    #expect(store.missingProductIDs == ["tip.missing"])
  }

  @Test func keepsTheErrorOfAFailedProductLoadUntilARefreshSucceeds() async {
    let mock = MockPurchaseClient()
    mock.products = [small]
    mock.productsError = PurchaseError(.networkUnavailable)
    let store = makeStore(mock, productIDs: ["tip.small"])

    await store.start()
    #expect(store.loadError?.code == .networkUnavailable)
    #expect(store.products.isEmpty)

    mock.productsError = nil
    await store.refresh()

    #expect(store.loadError == nil)
    #expect(store.products == [small])
  }

  @Test func loadingProductsReturnsThemInTheRequestedOrder() async throws {
    let mock = MockPurchaseClient()
    mock.products = [small, pro]
    let store = makeStore(mock, productIDs: ["pro.lifetime", "tip.small"])

    let loaded = try await store.loadProducts()

    #expect(loaded == [pro, small])
    #expect(store.products == [pro, small])
    #expect(store.isLoadingProducts == false)
  }

  @Test func aFailedLoadThrowsAndKeepsTheProductsAlreadyLoaded() async {
    let mock = MockPurchaseClient()
    mock.products = [small]
    let store = makeStore(mock, productIDs: ["tip.small"])
    await store.start()
    mock.productsError = PurchaseError(.networkUnavailable)

    var thrown: PurchaseError?
    do throws(PurchaseError) {
      try await store.loadProducts()
    } catch {
      thrown = error
    }

    #expect(thrown?.code == .networkUnavailable)
    #expect(store.products == [small])
    #expect(store.loadError?.code == .networkUnavailable)
    #expect(store.isLoadingProducts == false)
  }

  @Test func aLoadWhileAnotherRunsJoinsIt() async throws {
    let mock = MockPurchaseClient()
    mock.products = [small]
    let client = GatedProductsClient(mock: mock)
    let store = PurchaseStore(client: client, productIDs: ["tip.small"])

    let starting = Task { await store.start() }
    await client.gate.arrival()
    #expect(store.isLoadingProducts)
    // The opener inherits the main actor, so it runs only once the joining call suspends.
    let opener = Task { client.gate.open() }
    let joined = try await store.loadProducts()
    await starting.value
    await opener.value

    #expect(joined == [small])
    #expect(store.products == [small])
    #expect(store.isLoadingProducts == false)
    #expect(client.productsCallCount == 1)
  }

  @Test func aCancelledCallerDoesNotCutTheLoadShortForOthers() async throws {
    let mock = MockPurchaseClient()
    mock.products = [small]
    let client = GatedProductsClient(mock: mock)
    let store = PurchaseStore(client: client, productIDs: ["tip.small"])

    let cancelled = Task { try await store.loadProducts() }
    await client.gate.arrival()
    cancelled.cancel()
    let opener = Task { client.gate.open() }
    let joined = try await store.loadProducts()
    await opener.value

    #expect(joined == [small])
    #expect(try await cancelled.value == [small])
    #expect(store.products == [small])
    #expect(store.loadError == nil)
    #expect(store.isLoadingProducts == false)
    #expect(client.productsCallCount == 1)
  }

  @Test func refreshReloadsWhenAProductIsMissing() async {
    let mock = MockPurchaseClient()
    mock.products = []
    let store = makeStore(mock, productIDs: ["tip.small"])

    await store.start()
    #expect(store.missingProductIDs == ["tip.small"])

    mock.products = [small]
    await store.refresh()

    #expect(store.products == [small])
    #expect(store.missingProductIDs.isEmpty)
  }

  @Test func entitlementsAreComputedWhenProductsFailToLoad() async {
    let mock = MockPurchaseClient()
    mock.entitlements = [lifetime(1)]
    mock.productsError = PurchaseError(.networkUnavailable)
    let store = makeStore(mock)

    await store.start()

    #expect(store.purchasedProductIDs == ["pro.lifetime"])
  }

  // MARK: Restore

  @Test func restoreSyncsThenReturnsThePurchasedProductIDs() async throws {
    let mock = MockPurchaseClient()
    let store = makeStore(mock)
    await store.start()
    mock.entitlements = [lifetime(1)]

    let restored = try await store.restore()

    #expect(restored == ["pro.lifetime"])
    #expect(store.purchasedProductIDs == ["pro.lifetime"])
  }

  @Test func aSyncErrorPropagatesFromRestore() async {
    let mock = MockPurchaseClient()
    mock.syncResult = .failure(PurchaseError(.userCancelled))
    let store = makeStore(mock)

    do {
      _ = try await store.restore()
      Issue.record("restore() did not throw")
    } catch {
      #expect(error.code == .userCancelled)
    }
  }

  // MARK: Preview

  @Test func aPreviewStoreExposesTheGivenProductsAndPurchasedIDs() {
    let store = PurchaseStore.preview(
      products: [small, pro], purchasedProductIDs: ["pro.lifetime"])

    #expect(store.products == [small, pro])
    #expect(store.purchasedProductIDs == ["pro.lifetime"])
    #expect(store.isEntitled(to: Entitlement(["pro.lifetime"])))
  }

  @Test func aStartedPreviewStoreKeepsItsProductsAndPurchasedIDs() async {
    let store = PurchaseStore.preview(
      products: [small, pro], purchasedProductIDs: ["pro.lifetime"])

    await store.start()

    #expect(store.products == [small, pro])
    #expect(store.purchasedProductIDs == ["pro.lifetime"])
    #expect(store.missingProductIDs.isEmpty)
  }
}
