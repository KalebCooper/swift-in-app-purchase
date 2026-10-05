/// How a purchase that did not throw ended.
public enum PurchaseOutcome: Sendable {
  /// The purchase awaits approval, such as an Ask to Buy request. It arrives later as a
  /// transaction update.
  case pending
  /// The purchase completed and verified.
  case success(PurchaseTransaction)
  /// The customer dismissed the purchase sheet.
  case userCancelled
}
