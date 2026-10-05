import SwiftData

/// The coins one purchase granted. The balance is the sum of every grant, so a redelivered
/// purchase and a refund both leave it correct.
@Model
final class CoinGrant {
  var coins: Int
  @Attribute(.unique) var transactionID: UInt64

  init(coins: Int, transactionID: UInt64) {
    self.coins = coins
    self.transactionID = transactionID
  }
}
