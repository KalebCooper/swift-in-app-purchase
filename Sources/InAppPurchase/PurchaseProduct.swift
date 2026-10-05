import Foundation
import StoreKit

/// A product offered for sale, as a value the UI can render and a test can construct.
public struct PurchaseProduct: Hashable, Identifiable, Sendable {
  /// The product's description, localized for the current storefront.
  public let description: String
  /// The product's name, localized for the current storefront.
  public let displayName: String
  /// The product's price, formatted for the current storefront.
  public let displayPrice: String
  /// The identifier configured in App Store Connect.
  public let id: String
  /// The product's price in the storefront's currency.
  public let price: Decimal
  /// The StoreKit product this value was read from, for anything this type does not carry, such
  /// as subscription details. `nil` for a product a test or preview constructed.
  public let storeKitProduct: Product?
  /// What kind of product this is.
  public let type: Product.ProductType

  /// Creates a product from its storefront presentation.
  public init(
    description: String = "",
    displayName: String,
    displayPrice: String,
    id: String,
    price: Decimal,
    storeKitProduct: Product? = nil,
    type: Product.ProductType
  ) {
    self.description = description
    self.displayName = displayName
    self.displayPrice = displayPrice
    self.id = id
    self.price = price
    self.storeKitProduct = storeKitProduct
    self.type = type
  }
}
