import Foundation
import StoreKit

/// A verified record of a purchase, as a value a test can construct.
public struct PurchaseTransaction: Hashable, Identifiable, Sendable {
  /// The token the app attached to the purchase, or `nil` if it attached none.
  public let appAccountToken: UUID?
  /// When a subscription expires, or `nil` for a product that does not.
  public let expirationDate: Date?
  /// The transaction's unique identifier.
  public let id: UInt64
  /// Whether the customer upgraded to another subscription in the same group.
  public let isUpgraded: Bool
  /// The identifier of the first transaction in this one's renewal chain. It equals ``id`` for a
  /// transaction that is not a renewal.
  public let originalID: UInt64
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
  ///
  /// - Parameters:
  ///   - appAccountToken: The token the app attached to the purchase, or `nil` if it attached none.
  ///   - expirationDate: When a subscription expires, or `nil` for a product that does not.
  ///   - id: The transaction's unique identifier.
  ///   - isUpgraded: Whether the customer upgraded to another subscription in the same group.
  ///   - originalID: The first transaction in the renewal chain. Pass `nil` to use `id`.
  ///   - productID: The identifier of the product purchased.
  ///   - productType: What kind of product was purchased.
  ///   - purchaseDate: When the purchase was made. Defaults to now.
  ///   - quantity: How many of the product were purchased.
  ///   - revocationDate: When the App Store refunded or revoked the purchase, or `nil` while it
  ///     stands.
  ///   - storeKitTransaction: The StoreKit transaction this value was read from, or `nil` for one
  ///     a test or preview constructs.
  public init(
    appAccountToken: UUID? = nil,
    expirationDate: Date? = nil,
    id: UInt64,
    isUpgraded: Bool = false,
    originalID: UInt64? = nil,
    productID: String,
    productType: Product.ProductType,
    purchaseDate: Date = Date(),
    quantity: Int = 1,
    revocationDate: Date? = nil,
    storeKitTransaction: Transaction? = nil
  ) {
    self.appAccountToken = appAccountToken
    self.expirationDate = expirationDate
    self.id = id
    self.isUpgraded = isUpgraded
    self.originalID = originalID ?? id
    self.productID = productID
    self.productType = productType
    self.purchaseDate = purchaseDate
    self.quantity = quantity
    self.revocationDate = revocationDate
    self.storeKitTransaction = storeKitTransaction
  }
}
