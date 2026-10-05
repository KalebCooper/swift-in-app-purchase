import Foundation
import StoreKit

/// A verified record of a purchase, as a value a test can construct.
public struct PurchaseTransaction: Hashable, Identifiable, Sendable {
  /// When a subscription expires, or `nil` for a product that does not.
  public let expirationDate: Date?
  /// The transaction's unique identifier.
  public let id: UInt64
  /// The identifier of the product purchased.
  public let productID: String
  /// What kind of product was purchased.
  public let productType: Product.ProductType
  /// When the purchase was made.
  public let purchaseDate: Date
  /// How many of the product were purchased.
  public let quantity: Int
  /// When the App Store refunded or revoked the purchase, or `nil` while it stands.
  public let revocationDate: Date?
  /// The StoreKit transaction this value was read from, for anything this type does not carry,
  /// such as its signed JWS representation. `nil` for a transaction a test or preview constructed.
  public let storeKitTransaction: Transaction?

  /// Creates a transaction record.
  public init(
    expirationDate: Date? = nil,
    id: UInt64,
    productID: String,
    productType: Product.ProductType,
    purchaseDate: Date,
    quantity: Int = 1,
    revocationDate: Date? = nil,
    storeKitTransaction: Transaction? = nil
  ) {
    self.expirationDate = expirationDate
    self.id = id
    self.productID = productID
    self.productType = productType
    self.purchaseDate = purchaseDate
    self.quantity = quantity
    self.revocationDate = revocationDate
    self.storeKitTransaction = storeKitTransaction
  }
}
