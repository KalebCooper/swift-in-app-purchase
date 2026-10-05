import InAppPurchase
import InAppPurchaseTesting
import Testing

@MainActor
@Suite struct PurchaseStoreTests {
  @Test func aNewStoreOwnsNothingAndOffersNothing() {
    let store = PurchaseStore(client: MockPurchaseClient(), productIDs: [])

    #expect(store.entitlements.isEmpty)
    #expect(store.products.isEmpty)
  }
}
