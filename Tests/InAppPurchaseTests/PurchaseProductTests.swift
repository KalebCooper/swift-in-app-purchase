import Foundation
import InAppPurchase
import StoreKit
import Testing

@Suite struct PurchaseProductTests {
  @Test func defaultsEverythingButTheRequiredParameters() {
    let product = PurchaseProduct(
      displayName: "Small tip",
      displayPrice: "$0.99",
      id: "tip.small",
      type: .consumable
    )

    #expect(product.description.isEmpty)
    #expect(product.displayName == "Small tip")
    #expect(product.displayPrice == "$0.99")
    #expect(product.id == "tip.small")
    #expect(product.price == 0)
    #expect(product.storeKitProduct == nil)
    #expect(product.type == .consumable)
  }

  @Test func keepsEveryValueItWasCreatedWith() {
    let product = PurchaseProduct(
      description: "Say thanks",
      displayName: "Large tip",
      displayPrice: "$4.99",
      id: "tip.large",
      price: Decimal(string: "4.99") ?? 0,
      type: .consumable
    )

    #expect(product.description == "Say thanks")
    #expect(product.price == Decimal(string: "4.99"))
  }

  @Test func identifiesItselfByItsProductID() {
    let product = PurchaseProduct(
      displayName: "Pro",
      displayPrice: "$9.99",
      id: "pro.lifetime",
      type: .nonConsumable
    )

    #expect(product.id == "pro.lifetime")
  }

  @Test func productsWithTheSameValuesAreEqual() {
    func make() -> PurchaseProduct {
      PurchaseProduct(
        displayName: "Pro",
        displayPrice: "$9.99",
        id: "pro.lifetime",
        type: .nonConsumable
      )
    }

    #expect(make() == make())
  }
}
