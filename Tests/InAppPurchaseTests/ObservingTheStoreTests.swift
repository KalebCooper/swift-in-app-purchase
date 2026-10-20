import Foundation
import InAppPurchase
import InAppPurchaseTesting
import Observation
import Testing

/// Observing the store from outside SwiftUI with `Observations`, as the Using the Store Outside
/// SwiftUI article does.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct ObservingTheStoreTests {
  private let pro = PurchaseProduct(
    displayName: "Pro",
    displayPrice: "$9.99",
    id: "pro.lifetime",
    type: .nonConsumable
  )

  private func lifetime(_ id: UInt64) -> PurchaseTransaction {
    PurchaseTransaction(
      id: id,
      productID: "pro.lifetime",
      productType: .nonConsumable,
      purchaseDate: Date(timeIntervalSince1970: 1_800_000_000)
    )
  }

  @Test func observationsYieldsThePurchasedProductsThenEachChange() async throws {
    let mock = MockPurchaseClient()
    let store = PurchaseStore(client: mock, productIDs: ["pro.lifetime"])
    let changes = Observations { store.purchasedProductIDs }
    var iterator = changes.makeAsyncIterator()
    await store.start()

    #expect(await iterator.next() == [])

    mock.send(lifetime(1))

    #expect(await iterator.next() == ["pro.lifetime"])
  }

  @Test func observationsYieldsThePendingProducts() async throws {
    let mock = MockPurchaseClient()
    mock.purchaseResults["pro.lifetime"] = .success(.pending)
    let store = PurchaseStore(client: mock, productIDs: ["pro.lifetime"])
    let changes = Observations { store.pendingProductIDs }
    var iterator = changes.makeAsyncIterator()
    await store.start()

    #expect(await iterator.next() == [])

    _ = try await store.purchase(pro)

    #expect(await iterator.next() == ["pro.lifetime"])

    mock.send(lifetime(1))

    #expect(await iterator.next() == [])
  }
}
