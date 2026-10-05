import Foundation
import InAppPurchase
import InAppPurchaseTesting
import StoreKit
import SwiftData
import Testing

@testable import PurchaseExample

@MainActor
struct CoinDeliveryTests {
  @Test func deliversCoinsOnce() async throws {
    let container = try ModelContainer(
      for: CoinGrant.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let mock = MockPurchaseClient()
    mock.unfinishedTransactions = [
      PurchaseTransaction(id: 1, productID: "coins.100", productType: .consumable)
    ]
    let store = PurchaseStore(client: mock, productIDs: ["coins.100"])

    await store.start { event in
      try CoinDelivery.deliver(event, in: container.mainContext)
    }

    #expect(try balance(in: container) == 100)
    #expect(mock.finishedTransactions.map(\.id) == [1])
  }

  @Test func redeliveryGrantsNothingMore() async throws {
    let container = try makeContainer()
    let transaction = PurchaseTransaction(id: 1, productID: "coins.100", productType: .consumable)

    // The second launch sees the transaction again, as it would if finishing had been
    // interrupted after the handler returned.
    for _ in 1...2 {
      let mock = MockPurchaseClient()
      mock.unfinishedTransactions = [transaction]
      let store = PurchaseStore(client: mock, productIDs: ["coins.100"])
      await store.start { event in
        try CoinDelivery.deliver(event, in: container.mainContext)
      }
    }

    #expect(try balance(in: container) == 100)
  }

  @Test func revocationRemovesTheGrant() async throws {
    let container = try makeContainer()
    let mock = MockPurchaseClient()
    mock.unfinishedTransactions = [
      PurchaseTransaction(id: 1, productID: "coins.100", productType: .consumable)
    ]
    let store = PurchaseStore(client: mock, productIDs: ["coins.100"])
    await store.start { event in
      try CoinDelivery.deliver(event, in: container.mainContext)
    }
    _ = try await mock.nextFinishedTransaction()

    mock.send(
      PurchaseTransaction(
        id: 1,
        productID: "coins.100",
        productType: .consumable,
        revocationDate: Date()
      )
    )
    _ = try await mock.nextFinishedTransaction()

    #expect(try balance(in: container) == 0)
  }

  private func balance(in container: ModelContainer) throws -> Int {
    try container.mainContext.fetch(FetchDescriptor<CoinGrant>()).reduce(0) { $0 + $1.coins }
  }

  private func makeContainer() throws -> ModelContainer {
    try ModelContainer(
      for: CoinGrant.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
  }
}
