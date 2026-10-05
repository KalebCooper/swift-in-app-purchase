import Foundation
import InAppPurchase
import SwiftData

/// Grants coins for a purchase and takes them back when the purchase is refunded.
@MainActor
enum CoinDelivery {
  /// The coins in each pack, by product identifier.
  static let coinsPerPack = ["coins.100": 100, "coins.500": 500]

  /// Records the coins `event` grants, or removes them when it is a revocation. Saves before
  /// returning, because the store finishes the transaction as soon as the handler returns.
  static func deliver(_ event: TransactionEvent, in context: ModelContext) throws {
    switch event {
    case .purchased(let transaction):
      // A transaction can arrive more than once, so grant its coins only the first time.
      guard try grants(for: transaction, in: context).isEmpty else { return }
      let coins = coinsPerPack[transaction.productID, default: 0] * transaction.quantity
      context.insert(CoinGrant(coins: coins, transactionID: transaction.id))
    case .revoked(let transaction):
      // A revocation carries the id of the purchase it revokes.
      for grant in try grants(for: transaction, in: context) {
        context.delete(grant)
      }
    }
    try context.save()
  }

  private static func grants(
    for transaction: PurchaseTransaction,
    in context: ModelContext
  ) throws -> [CoinGrant] {
    let id = transaction.id
    return try context.fetch(
      FetchDescriptor<CoinGrant>(predicate: #Predicate { $0.transactionID == id })
    )
  }
}
