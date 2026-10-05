import Foundation
import InAppPurchase
import InAppPurchaseTesting
import Testing

@MainActor
@Suite struct PurchaseStoreTests {
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
    #expect(recorder.maxActive == 1)
  }

  @Test func aRevocationReachesTheHandlerAsRevokedAndDropsTheEntitlement() async throws {
    let mock = MockPurchaseClient()
    mock.entitlements = [lifetime(1)]
    let recorder = HandlerRecorder(mock: mock)
    let store = makeStore(mock)
    await store.start(handling: recorder.handle)
    #expect(store.purchasedProductIDs == ["pro.lifetime"])
    let revocation = PurchaseTransaction(
      id: 1,
      productID: "pro.lifetime",
      productType: .nonConsumable,
      purchaseDate: purchaseDate,
      revocationDate: purchaseDate.addingTimeInterval(60)
    )

    mock.entitlements = []
    mock.send(revocation)

    #expect(try await mock.nextFinishedTransaction() == revocation)
    #expect(recorder.events.map(\.revoked) == [revocation])
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
      let store = makeStore(mock)
      await store.start(handling: recorder.handle)
      mock.send(tip(1))
      _ = try await mock.nextFinishedTransaction()
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

    let outcome = try await store.purchase(pro)
    if case .pending = outcome {} else { Issue.record("expected .pending") }
    #expect(recorder.events.isEmpty)

    mock.send(lifetime(1))

    #expect(try await mock.nextFinishedTransaction() == lifetime(1))
    #expect(recorder.events.map(\.purchased) == [lifetime(1)])
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

  private var expiredMonthly: PurchaseTransaction {
    PurchaseTransaction(
      expirationDate: Date(timeIntervalSinceNow: -60),
      id: 24,
      productID: "pro.monthly",
      productType: .autoRenewable,
      purchaseDate: purchaseDate
    )
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

  @Test(arguments: ["revoked", "upgraded", "non-renewing", "expired"])
  func excludesFromPurchased(_ kind: String) async {
    let mock = MockPurchaseClient()
    switch kind {
    case "revoked": mock.entitlements = [revokedLifetime]
    case "upgraded": mock.entitlements = [upgradedMonthly]
    case "non-renewing": mock.entitlements = [season]
    default: mock.entitlements = [expiredMonthly]
    }
    let store = makeStore(mock)

    await store.start()

    #expect(store.purchasedProductIDs.isEmpty)
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
    let later = Date(timeIntervalSinceNow: 7_200)
    let monthlySoon = PurchaseTransaction(
      expirationDate: Date(timeIntervalSinceNow: 3_600),
      id: 20,
      productID: "pro.monthly",
      productType: .autoRenewable
    )
    let yearly = PurchaseTransaction(
      expirationDate: later,
      id: 26,
      productID: "pro.yearly",
      productType: .autoRenewable
    )
    mock.entitlements = [monthlySoon, yearly]
    let sleep = ControlledSleep()
    let store = PurchaseStore(
      client: mock, productIDs: ["pro.monthly", "pro.yearly"], sleep: sleep.sleep(for:))
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

  @Test func anOlderRecomputeThatFinishesLateDoesNotOverwriteANewerOne() async {
    let mock = MockPurchaseClient()
    mock.entitlements = [lifetime(1)]
    let client = GatedEntitlementsClient(mock: mock, gatedCall: 2)
    let store = PurchaseStore(client: client, productIDs: ["pro.lifetime", "pro.monthly"])
    await store.start()
    #expect(store.purchasedProductIDs == ["pro.lifetime"])

    mock.entitlements = []
    let older = Task { await store.refresh() }
    await client.gate.arrival()
    mock.entitlements = [monthly]
    await store.refresh()
    #expect(store.purchasedProductIDs == ["pro.monthly"])

    client.gate.open()
    await older.value

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
