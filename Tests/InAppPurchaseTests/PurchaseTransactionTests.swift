import Foundation
import InAppPurchase
import Testing

@Suite struct PurchaseTransactionTests {
  private let purchaseDate = Date(timeIntervalSince1970: 1_800_000_000)

  @Test func defaultsEverythingButTheRequiredParameters() {
    let transaction = PurchaseTransaction(
      id: 7,
      productID: "tip.small",
      productType: .consumable
    )

    #expect(transaction.appAccountToken == nil)
    #expect(transaction.expirationDate == nil)
    #expect(transaction.id == 7)
    #expect(transaction.isUpgraded == false)
    #expect(transaction.productID == "tip.small")
    #expect(transaction.productType == .consumable)
    #expect(transaction.quantity == 1)
    #expect(transaction.revocationDate == nil)
    #expect(transaction.storeKitTransaction == nil)
  }

  @Test func theOriginalIDDefaultsToTheTransactionID() {
    let transaction = PurchaseTransaction(
      id: 42,
      productID: "pro.monthly",
      productType: .autoRenewable
    )

    #expect(transaction.originalID == 42)
  }

  @Test func keepsAnOriginalIDItWasGiven() {
    let transaction = PurchaseTransaction(
      id: 42,
      originalID: 7,
      productID: "pro.monthly",
      productType: .autoRenewable
    )

    #expect(transaction.id == 42)
    #expect(transaction.originalID == 7)
  }

  @Test func keepsEveryValueItWasCreatedWith() {
    let token = UUID()
    let expiration = purchaseDate.addingTimeInterval(86_400)
    let revocation = purchaseDate.addingTimeInterval(3_600)

    let transaction = PurchaseTransaction(
      appAccountToken: token,
      expirationDate: expiration,
      id: 9,
      isUpgraded: true,
      originalID: 3,
      productID: "pro.monthly",
      productType: .autoRenewable,
      purchaseDate: purchaseDate,
      quantity: 2,
      revocationDate: revocation
    )

    #expect(transaction.appAccountToken == token)
    #expect(transaction.expirationDate == expiration)
    #expect(transaction.isUpgraded)
    #expect(transaction.originalID == 3)
    #expect(transaction.purchaseDate == purchaseDate)
    #expect(transaction.quantity == 2)
    #expect(transaction.revocationDate == revocation)
  }

  @Test func transactionsWithTheSameValuesAreEqual() {
    func make() -> PurchaseTransaction {
      PurchaseTransaction(
        id: 1,
        productID: "tip.small",
        productType: .consumable,
        purchaseDate: Date(timeIntervalSince1970: 1_800_000_000)
      )
    }

    #expect(make() == make())
  }

  @Test func aRevocationIsADifferentValueFromThePurchaseItReverses() {
    let purchase = PurchaseTransaction(
      id: 1,
      productID: "tip.small",
      productType: .consumable,
      purchaseDate: purchaseDate
    )
    let revocation = PurchaseTransaction(
      id: 1,
      productID: "tip.small",
      productType: .consumable,
      purchaseDate: purchaseDate,
      revocationDate: purchaseDate.addingTimeInterval(60)
    )

    #expect(purchase.id == revocation.id)
    #expect(purchase != revocation)
  }
}
